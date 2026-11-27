import {
  cors,
  database,
  handle,
  json,
  PaymentError,
  record,
  secureUrl,
  uuid,
  type Fetch,
  type RecordData,
  type Settings,
} from './payment_http.ts';

type PaymentStatus = 'unpaid' | 'pending' | 'failed' | 'cancelled' | 'paid';
type FinalStatus = 'failed' | 'cancelled' | 'paid';
type CheckoutAction = 'open' | 'status' | 'cancel';
type Attempt = {
  id: string | null;
  amount_centavos: number;
  checkout_id: string | null;
  checkout_url: string | null;
  created_at?: string;
  can_create: boolean;
  status: PaymentStatus;
  provider?: 'maya' | 'paymongo';
};
type Payment = {
  id: string;
  reference: string;
  cents: number;
  status: FinalStatus | 'pending';
};
type Database = ReturnType<typeof database>;

const sandboxOrigin = 'https://pg-sandbox.paymaya.com';
const sandboxCheckoutHosts = new Set(['payments-web-sandbox.maya.ph', 'payments-web-sandbox.paymaya.com']);
const unresolvedCheckoutWindowMs = 65 * 60_000;

// Maya's two published sandbox signing public keys, for rotation without downtime.
const sandboxSigningKeys = [
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAjNkSX6p+goDPaPAYuTzT' +
  'zKTCBeLhh8FkPMbZxDKTUxF93dOwiC7jsdx7KyopupeLosiVlbs+gpAJ7XBQP/Ex' +
  'giyzXC9TljpyvkUQfyRPMAMKq+BzxdUliTl6hgrLBsH28CP5FuPHCsfxDXe7mDtv' +
  '9H4mP3SKO0HfkZ45tudxD9CWbwWKF0lU9LRbLlJ0y7KEaK7Rv9fI1Dp/KPT+9pls' +
  'tU+CPNKaxJjGRKGuxW2AOCabSD0cTZNXki+K51mNoma7Mj1HMhnsR68FGJvCqk1q' +
  'Wsr3q8+EUMVPBMX+5nKATfZYGvxg4ytzT8pnEVeWl6phYKviB9aVVwurh1gDJB4r' +
  'lQIDAQAB',
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAp14gezqq4dGWu7EZ7BHx' +
  '8wD3y1hqxwQR7UYPXtXJP+WngN4wqwatjsnQaRGnmdPRG8VEzUzw9PlR7t7P24uW' +
  '+J08xBrtTVouD2MKglcIcy13rt1XL79zr/LIAFMFI6f4O8/OQi1xsGsZ6xarD+wl' +
  'OQKG4W66I3yp2jNAbge25eSPuo0BNqPWvebMcIYJu4f3Fxu1eDgeM6zCEqLc6+jX' +
  'cNTP/zFHCvQaiIlLOqfgXDRPBcHPPZ2qcB99UVPAHXBKsKdtBB2w2qT2l99MlTAB' +
  'iRy+IKtVQcQyRP7T8blegO25x35G2CZ3VCKPkmUen3eXQ4+r5fVlzEIBSfNvBwT9' +
  'jQIDAQAB',
];

function provider(settings: Settings, request: Fetch) {
  function authHeader(kind: 'public' | 'secret'): string {
    const name = kind === 'public' ? 'MAYA_SANDBOX_PUBLIC_KEY' : 'MAYA_SANDBOX_SECRET_KEY';
    const prefix = kind === 'public' ? 'pk-' : 'sk-';
    const key = settings(name);
    if (!key?.startsWith(prefix)) throw new PaymentError(503, 'Maya sandbox is unavailable.');
    return `Basic ${btoa(`${key}:`)}`;
  }

  async function send(path: string, authorization: string, options: RequestInit, timeout = 3000) {
    return await request(`${sandboxOrigin}${path}`, {
      ...options,
      headers: { Authorization: authorization, 'Content-Type': 'application/json', Accept: 'application/json' },
      redirect: 'error',
      signal: AbortSignal.timeout(timeout),
    });
  }

  async function payload(response: Response): Promise<unknown> {
    if (!response.ok) throw new PaymentError(502, 'Maya could not verify this sandbox checkout. Try again.');
    return await response.json();
  }

  return {
    publicAuthorization: () => authHeader('public'),
    secretAuthorization: () => authHeader('secret'),
    create: async (authorization: string, details: RecordData) => {
      const response = await send('/checkout/v1/checkouts', authorization, {
        method: 'POST', body: JSON.stringify(details),
      }, 12_000);
      if (response.status === 401 || response.status === 403) return null;
      if (response.status === 400 || response.status === 422) {
        const error = record(await response.json().catch(() => null));
        if (error.code === '2553') return null;
        throw new PaymentError(502, 'Maya could not create this sandbox checkout. Check its status before retrying.');
      }
      return record(await payload(response));
    },
    payment: async (id: string, authorization: string) => record(await payload(await send(
      `/payments/v1/payments/${id}`, authorization, {},
    ))),
    paymentsByReference: async (reference: string, authorization: string) => {
      const response = await send(`/payments/v1/payment-rrns/${reference}`, authorization, {});
      if (response.status === 404) {
        const error = record(await response.json().catch(() => null));
        if (error.code === 'PY0009') return [];
        throw new PaymentError(502, 'Maya could not verify the sandbox payment reference.');
      }
      const payments = await payload(response);
      if (!Array.isArray(payments)) throw new PaymentError(502, 'Maya returned unexpected payment details.');
      return payments.map(record);
    },
    cancel: async (id: string, authorization: string) => {
      // Maya refuses cancellation once authentication or payment has progressed.
      // Retrieve the provider state separately even when the cancel request fails.
      await send(`/payments/v1/payments/${id}/cancel`, authorization, { method: 'POST' })
        .then((response) => response.body?.cancel()).catch(() => undefined);
    },
  };
}

function asCents(value: unknown): number | null {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value));
  if (!match) return null;
  const cents = Number(match[1]) * 100 + Number((match[2] ?? '').padEnd(2, '0'));
  return Number.isSafeInteger(cents) && cents > 0 && cents <= 2_147_483_647 ? cents : null;
}

function observedStatus(status: unknown): Payment['status'] {
  switch (status) {
    case 'PAYMENT_SUCCESS': return 'paid';
    case 'PAYMENT_FAILED':
    case 'AUTH_FAILED': return 'failed';
    case 'PAYMENT_CANCELLED':
    case 'PAYMENT_EXPIRED': return 'cancelled';
    default: return 'pending';
  }
}

function providerPayment(body: RecordData, expectedId?: string): Payment | null {
  const id = body.id;
  const reference = body.requestReferenceNumber;
  if (typeof id !== 'string' || !uuid.test(id) || (expectedId && id !== expectedId)) {
    throw new PaymentError(502, 'Maya returned a different payment.');
  }
  if (typeof reference !== 'string' || !uuid.test(reference)) return null;
  const total = record(body.totalAmount);
  const cents = asCents(body.amount ?? total.value);
  const currency = body.currency ?? total.currency;
  const status = observedStatus(body.paymentStatus ?? body.status);
  if (cents == null || currency !== 'PHP' ||
    (total.value != null && asCents(total.value) !== cents) ||
    (total.currency != null && total.currency !== currency) ||
    (status === 'paid' && body.isPaid === false)) {
    throw new PaymentError(502, 'Maya returned unexpected payment details.');
  }
  return { id, reference, cents, status };
}

function checkoutUrl(value: unknown): string | null {
  const url = secureUrl(value);
  return url && sandboxCheckoutHosts.has(url.host) ? url.href : null;
}

function checkoutResponse(attempt: Attempt): Response {
  const provider = attempt.provider ?? 'maya';
  return json({
    provider,
    status: attempt.status,
    checkout_url: provider === 'maya' && attempt.status === 'pending' ? checkoutUrl(attempt.checkout_url) : null,
  });
}

function requireBinding(attempt: Attempt, payment: Payment | null): Payment {
  if (!payment || payment.reference !== attempt.id || payment.cents !== attempt.amount_centavos) {
    throw new PaymentError(409, 'Maya payment details do not match this booking.');
  }
  return payment;
}

function saveCheckout(db: Database, attemptId: string, id: string, url: string | null) {
  return db.rpc<Attempt>('maya_save_checkout', {
    p_attempt_id: attemptId,
    p_checkout_id: id,
    p_checkout_url: url,
  });
}

function releaseUncreated(db: Database, attemptId: string, definitive: boolean) {
  return db.rpc<Attempt>('maya_release_uncreated', {
    p_attempt_id: attemptId,
    p_definitive: definitive,
  });
}

function settle(db: Database, payment: Payment) {
  return db.rpc<Attempt | { status: 'unmatched' | 'unbound' }>('maya_record_payment', {
    p_attempt_id: payment.reference,
    p_checkout_id: payment.id,
    p_status: payment.status,
    p_amount_centavos: payment.cents,
    p_currency: 'PHP',
    p_payment_id: payment.id,
  });
}

function returnLink(settings: Settings): string {
  const configured = settings('MAYA_RETURN_URL');
  const project = secureUrl(settings('SUPABASE_URL'));
  const url = configured ? secureUrl(configured) : project && new URL('/functions/v1/maya-checkout', project);
  if (!url) throw new PaymentError(503, 'Maya sandbox is unavailable.');
  return url.href;
}

export function checkoutHandler(settings: Settings, request: Fetch = fetch) {
  return (message: Request): Promise<Response> => handle(async () => {
    if (message.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (message.method === 'GET') {
      return new Response('Return to GoMigo to check your Maya sandbox payment status.', {
        headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
      });
    }
    if (message.method !== 'POST') return json({ error: 'Method unavailable.' }, 405);

    const input = record(await message.json().catch(() => null));
    const bookingId = input.booking_id;
    const action = input.action ?? 'open';
    if (typeof bookingId !== 'string' || !uuid.test(bookingId) ||
      (action !== 'open' && action !== 'status' && action !== 'cancel')) {
      return json({ error: 'Enter a booking ID and a supported action.' }, 400);
    }

    const db = database(settings, request);
    const travelerId = await db.travelerId(message.headers.get('Authorization'));
    const lookup = (create: boolean) => db.rpc<Attempt>('maya_checkout_for_traveler', {
      p_booking_id: bookingId, p_traveler_id: travelerId, p_create: create,
    });
    let attempt = await lookup(false);
    if (attempt.provider === 'paymongo' || attempt.status === 'paid') return checkoutResponse(attempt);

    const maya = provider(settings, request);
    if (attempt.status !== 'pending') {
      if (action !== 'open') return checkoutResponse(attempt);
      const successUrl = returnLink(settings);
      const publicAuth = maya.publicAuthorization();
      maya.secretAuthorization();
      attempt = await lookup(true);
      if (attempt.can_create && attempt.id) {
        const created = await maya.create(publicAuth, {
          totalAmount: { value: attempt.amount_centavos / 100, currency: 'PHP' },
          requestReferenceNumber: attempt.id,
          redirectUrl: { success: successUrl, failure: successUrl, cancel: successUrl },
        });
        if (!created) {
          await releaseUncreated(db, attempt.id, true);
          throw new PaymentError(502, 'Maya rejected the sandbox checkout. Check the sandbox setup and try again.');
        }
        const id = created.checkoutId;
        const url = checkoutUrl(created.redirectUrl);
        if (typeof id !== 'string' || !uuid.test(id)) {
          throw new PaymentError(502, 'Maya returned an unexpected sandbox checkout.');
        }
        const saved = await saveCheckout(db, attempt.id, id, url);
        if (!url) throw new PaymentError(502, 'Maya returned an unsupported sandbox checkout link.');
        return checkoutResponse(saved);
      }
    }

    if (attempt.status !== 'pending' || !attempt.id) return checkoutResponse(attempt);
    return await refreshCheckout(db, maya, attempt, action);
  });
}

async function refreshCheckout(db: Database, maya: ReturnType<typeof provider>, attempt: Attempt, action: CheckoutAction) {
  const authorization = maya.secretAuthorization();
  const attemptId = attempt.id!;
  let payment: Payment;
  if (!attempt.checkout_id) {
    // Maya Checkout does not document idempotent creation. Never send a second create for this claim.
    const available = await maya.paymentsByReference(attemptId, authorization);
    if (available.length === 0) {
      const age = Date.now() - Date.parse(attempt.created_at ?? '');
      if (age >= unresolvedCheckoutWindowMs) {
        return checkoutResponse(await releaseUncreated(db, attemptId, false));
      }
      return checkoutResponse(attempt);
    }
    if (available.length !== 1) throw new PaymentError(409, 'This Maya checkout needs reconciliation.');
    payment = requireBinding(attempt, providerPayment(available[0]));
    attempt = await saveCheckout(db, attemptId, payment.id, null);
  } else {
    payment = requireBinding(attempt, providerPayment(await maya.payment(attempt.checkout_id, authorization), attempt.checkout_id));
  }

  if (action === 'cancel' && payment.status === 'pending') {
    await maya.cancel(payment.id, authorization);
    payment = requireBinding(attempt, providerPayment(await maya.payment(payment.id, authorization), payment.id));
    if (payment.status === 'pending') {
      throw new PaymentError(409, 'Maya has not confirmed cancellation. Check the checkout status again.');
    }
  }
  if (payment.status === 'pending') return checkoutResponse(attempt);

  const result = await settle(db, payment);
  if (!('checkout_id' in result)) throw new PaymentError(409, 'Maya payment could not be matched to this booking.');
  return checkoutResponse(result);
}

function flatten(value: RecordData | unknown[], prefix = '', pairs: string[] = []): string[] {
  for (const [key, entry] of Object.entries(value)) {
    if (entry == null || entry === '') continue;
    const name = prefix ? `${prefix}.${key}` : key;
    if (typeof entry === 'object') flatten(entry as RecordData, name, pairs);
    else pairs.push(`${name}=${entry}`);
  }
  return pairs;
}

async function validSignature(headers: Headers, payload: RecordData, keys: readonly string[]): Promise<boolean> {
  const timestamp = headers.get('X-Maya-Webhook-Timestamp') ?? '';
  if (!/^\d{13}$/.test(timestamp) || Math.abs(Date.now() - Number(timestamp)) > 300_000) return false;
  const fields = new URLSearchParams((headers.get('X-Maya-Webhook-Signature') ?? '').replace(/,\s*/g, '&'));
  const nonce = fields.get('nonce') ?? '';
  const signature = fields.get('v1') ?? '';
  if (!/^[a-zA-Z0-9_-]{1,128}$/.test(nonce) || !/^(?:[0-9a-f]{2}){256,512}$/i.test(signature) ||
    fields.getAll('nonce').length !== 1 || fields.getAll('v1').length !== 1) return false;

  const body = new TextEncoder().encode(`${flatten(payload).sort().join('&')}&nonce=${nonce}`);
  const bytes = Uint8Array.from(signature.match(/../g)!, (pair) => parseInt(pair, 16));
  for (const encoded of keys) {
    const publicKey = await crypto.subtle.importKey(
      'spki', Uint8Array.from(atob(encoded), (byte) => byte.charCodeAt(0)),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
    );
    if (await crypto.subtle.verify('RSASSA-PKCS1-v1_5', publicKey, bytes, body)) return true;
  }
  return false;
}

export function webhookHandler(settings: Settings, request: Fetch = fetch, signingKeys = sandboxSigningKeys) {
  return (message: Request): Promise<Response> => handle(async () => {
    if (message.method !== 'POST') return json({ error: 'Method unavailable.' }, 405);
    const body = await message.text();
    if (body.length > 256_000) return json({ error: 'Webhook too large.' }, 413);
    let event: RecordData;
    try {
      event = record(JSON.parse(body));
    } catch {
      return json({ error: 'Invalid webhook body.' }, 400);
    }
    if (!await validSignature(message.headers, event, signingKeys)) {
      return json({ error: 'Invalid Maya sandbox webhook signature.' }, 401);
    }
    const id = event.id;
    if (typeof id !== 'string' || !uuid.test(id)) return json({ error: 'Missing Maya payment ID.' }, 400);

    // A signed notification is only a hint. Fetch current state from our sandbox merchant account.
    const maya = provider(settings, request);
    const payment = providerPayment(await maya.payment(id, maya.secretAuthorization()), id);
    if (!payment) return json({ status: 'ignored' });
    if (payment.status === 'pending') return json({ error: 'Maya payment is still being verified.' }, 503);
    const result = await settle(database(settings, request, 1700), payment);
    if (result.status === 'unbound') return json({ error: 'Maya checkout record is being saved.' }, 503);
    return json({ status: result.status === 'unmatched' ? 'ignored' : result.status });
  });
}
