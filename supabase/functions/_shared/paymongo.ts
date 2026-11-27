type Fetch = typeof fetch;
type Settings = (name: string) => string | undefined;
type RecordData = Record<string, unknown>;
type PaymentStatus = 'unpaid' | 'pending' | 'failed' | 'cancelled' | 'paid';
type Checkout = {
  id: string | null;
  amount_centavos: number | null;
  checkout_id: string | null;
  checkout_url: string | null;
  status: PaymentStatus;
  created_at: string | null;
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const checkoutIdPattern = /^cs_[a-zA-Z0-9]+$/;
const paymentIdPattern = /^pay_[a-zA-Z0-9]+$/;
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

class PaymentError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function record(value: unknown): RecordData {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as RecordData
    : {};
}

function secureUrl(value: unknown): URL | undefined {
  if (typeof value !== 'string') return;
  try {
    const url = new URL(value);
    if (url.protocol === 'https:' && !url.username && !url.password) return url;
  } catch {
    return undefined;
  }
}

function json(value: RecordData, status = 200): Response {
  return Response.json(value, { status, headers: { ...cors, 'Cache-Control': 'no-store' } });
}

async function handle(operation: () => Promise<Response>): Promise<Response> {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof PaymentError) return json({ error: error.message }, error.status);
    return json({ error: 'Test payment service is temporarily unavailable.' }, 503);
  }
}

function database(settings: Settings, request: Fetch) {
  const base = settings('SUPABASE_URL');
  const keys = settings('SUPABASE_SECRET_KEYS');
  const key = (keys && record(JSON.parse(keys)).default) || settings('SUPABASE_SERVICE_ROLE_KEY');
  if (!base || typeof key !== 'string' || !key) {
    throw new PaymentError(503, 'The test payment backend is unavailable.');
  }
  const headers: Record<string, string> = { apikey: key };
  if (!key.startsWith('sb_secret_')) headers.Authorization = `Bearer ${key}`;

  return {
    async travelerId(authorization: string | null): Promise<string> {
      if (!authorization || !/^Bearer \S+$/i.test(authorization)) {
        throw new PaymentError(401, 'Sign in to manage test payments.');
      }
      const response = await request(`${base}/auth/v1/user`, {
        headers: { ...headers, Authorization: authorization },
        signal: AbortSignal.timeout(8000),
      });
      if (response.status === 401 || response.status === 403) {
        throw new PaymentError(401, 'Sign in to manage test payments.');
      }
      if (!response.ok) throw new PaymentError(503, 'Could not verify the session.');
      const user = record(await response.json());
      if (typeof user.id !== 'string' || !uuid.test(user.id) || user.is_anonymous === true) {
        throw new PaymentError(401, 'Sign in to manage test payments.');
      }
      return user.id;
    },
    async rpc<T>(name: string, args: RecordData): Promise<T> {
      const response = await request(`${base}/rest/v1/rpc/${name}`, {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(8000),
      });
      const body = await response.json();
      if (!response.ok) {
        switch (record(body).code) {
          case 'GM404':
            throw new PaymentError(404, 'Booking unavailable.');
          case 'GM409':
            throw new PaymentError(409, 'This booking is no longer eligible for checkout.');
          default:
            throw new PaymentError(503, 'Could not save or read the test payment. Try again.');
        }
      }
      return body as T;
    },
  };
}

function provider(settings: Settings, request: Fetch) {
  const key = settings('PAYMONGO_TEST_SECRET_KEY');
  if (!key?.startsWith('sk_test_')) {
    throw new PaymentError(503, 'PayMongo test mode is unavailable.');
  }
  return async (path: string, options: RequestInit = {}): Promise<Response> => {
    return await request(`https://api.paymongo.com${path}`, {
      ...options,
      headers: {
        Authorization: `Basic ${btoa(`${key}:`)}`,
        'Content-Type': 'application/json',
        ...options.headers,
      },
      redirect: 'error',
      signal: AbortSignal.timeout(8000),
    });
  };
}

async function providerCheckout(response: Response, reference: string, checkoutId?: string) {
  if (!response.ok) {
    throw new PaymentError(502, 'PayMongo could not process this test checkout. Try again.');
  }
  const session = record(record(await response.json()).data);
  const details = record(session.attributes);
  if (
    session.type !== 'checkout_session' || typeof session.id !== 'string' ||
    !checkoutIdPattern.test(session.id) || (checkoutId && session.id !== checkoutId) ||
    details.livemode !== false || details.reference_number !== reference
  ) {
    throw new PaymentError(502, 'PayMongo returned an unexpected checkout.');
  }
  return { id: session.id, details };
}

function checkoutResponse(checkout: Checkout): Response {
  const active = checkout.status === 'pending' || checkout.status === 'failed';
  return json({
    status: checkout.status,
    checkout_url: active ? checkout.checkout_url : null,
  });
}

export function checkoutHandler(settings: Settings, request: Fetch = fetch) {
  return (message: Request): Promise<Response> => handle(async () => {
    if (message.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (message.method === 'GET') {
      return new Response('Return to GoMigo to check your test payment status.', {
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
    const lookup = {
      p_booking_id: bookingId,
      p_traveler_id: travelerId,
      p_create: false,
    };
    let checkout = await db.rpc<Checkout>('paymongo_checkout_for_traveler', lookup);
    if (checkout.status === 'paid') return checkoutResponse(checkout);

    if (!checkout.id || checkout.status === 'cancelled') {
      if (action !== 'open') return checkoutResponse(checkout);
      // Verify configuration before reserving a payment on the booking.
      provider(settings, request);
      if (!secureUrl(settings('PAYMONGO_RETURN_URL')) || !settings('PAYMONGO_WEBHOOK_SECRET')) {
        return json({ error: 'PayMongo test mode is unavailable.' }, 503);
      }
      checkout = await db.rpc<Checkout>('paymongo_checkout_for_traveler', {
        ...lookup,
        p_create: true,
      });
    }
    if (checkout.status === 'paid') return checkoutResponse(checkout);
    if (!checkout.id) return checkoutResponse(checkout);

    if (!checkout.checkout_id) {
      if (action === 'status') return checkoutResponse(checkout);
      if (action === 'cancel') {
        return json({ error: 'Retry opening the test checkout before cancelling it.' }, 409);
      }
      const returnUrl = secureUrl(settings('PAYMONGO_RETURN_URL'));
      if (!returnUrl || !settings('PAYMONGO_WEBHOOK_SECRET')) {
        return json({ error: 'PayMongo test mode is unavailable.' }, 503);
      }
      // shortcut: Reconcile uncertain creations manually before retrying outside PayMongo's idempotency window.
      if (!checkout.created_at || Date.now() - Date.parse(checkout.created_at) >= 23 * 3_600_000) {
        return json({ error: 'Test checkout needs reconciliation before you can retry.' }, 409);
      }
      const paymongo = provider(settings, request);
      const response = await paymongo('/v2/checkout_sessions', {
        method: 'POST',
        headers: { 'Idempotency-Key': checkout.id },
        body: JSON.stringify({
          data: {
            attributes: {
              line_items: [{
                name: 'GoMigo booking (test payment)',
                amount: checkout.amount_centavos,
                currency: 'PHP',
                quantity: 1,
              }],
              payment_method_types: ['card'],
              success_url: returnUrl.href,
              cancel_url: returnUrl.href,
              reference_number: checkout.id,
              send_email_receipt: false,
              pass_on_fees: false,
            },
          },
        }),
      });
      const session = await providerCheckout(response, checkout.id);
      const url = secureUrl(session.details.checkout_url);
      if (!url || url.host !== 'checkout.paymongo.com' || session.details.status !== 'active') {
        return json({ error: 'PayMongo returned an unexpected checkout.' }, 502);
      }
      checkout = await db.rpc<Checkout>('paymongo_save_checkout', {
        p_attempt_id: checkout.id,
        p_checkout_id: session.id,
        p_checkout_url: url.href,
      });
      return checkoutResponse(checkout);
    }

    const paymongo = provider(settings, request);
    const path = `/v1/checkout_sessions/${encodeURIComponent(checkout.checkout_id)}`;
    let response = action === 'cancel'
      ? await paymongo(`${path}/expire`, { method: 'POST' })
      : await paymongo(path);
    if (action === 'cancel' && response.status === 400) response = await paymongo(path);
    const session = await providerCheckout(response, checkout.id, checkout.checkout_id);
    const intent = record(record(session.details.payment_intent).attributes);
    const payments = Array.isArray(session.details.payments) ? session.details.payments : [];
    const paid = payments.some((payment) => record(record(payment).attributes).status === 'paid') ||
      intent.status === 'succeeded';
    if (paid) {
      // A successful redirect or API read can arrive before the signed webhook.
      checkout = await db.rpc<Checkout>('paymongo_checkout_for_traveler', lookup);
      return json({ status: checkout.status === 'paid' ? 'paid' : 'pending', checkout_url: null });
    }
    if (session.details.status !== 'active' && session.details.status !== 'expired') {
      return json({ error: 'PayMongo returned an unexpected checkout state.' }, 502);
    }
    if (action === 'cancel' && session.details.status !== 'expired') {
      return json({ error: 'This test payment is processing. Refresh the status and try again.' }, 409);
    }
    const declined = intent.status === 'awaiting_payment_method' && intent.last_payment_error != null;
    const status = session.details.status === 'expired' ? 'cancelled' : declined ? 'failed' : 'pending';
    if (checkout.status !== status) {
      checkout = await db.rpc<Checkout>('paymongo_refresh_checkout', {
        p_attempt_id: checkout.id,
        p_checkout_id: session.id,
        p_status: status,
      });
    }
    return checkoutResponse(checkout);
  });
}

async function validSignature(header: string | null, body: Uint8Array<ArrayBuffer>, secret: string) {
  const fields = new URLSearchParams((header ?? '').replace(/,\s*/g, '&'));
  const timestamp = fields.get('t') ?? '';
  const signature = fields.get('te') ?? '';
  if (!/^\d{1,12}$/.test(timestamp) || !/^[a-f\d]{64}$/i.test(signature) ||
    fields.getAll('t').length !== 1 || fields.getAll('te').length !== 1 || fields.get('li')) {
    return false;
  }
  // PayMongo retries deliveries over multiple hours. The durable payment ID handles replays.
  const ageSeconds = Date.now() / 1000 - Number(timestamp);
  if (ageSeconds < -300 || ageSeconds > 7 * 86400) return false;
  const encoder = new TextEncoder();
  const prefix = encoder.encode(`${timestamp}.`);
  const signed = new Uint8Array(prefix.length + body.length);
  signed.set(prefix);
  signed.set(body, prefix.length);
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'],
  );
  const bytes = Uint8Array.from(signature.match(/../g)!, (pair) => parseInt(pair, 16));
  return await crypto.subtle.verify('HMAC', key, bytes, signed);
}

export function webhookHandler(settings: Settings, request: Fetch = fetch) {
  return (message: Request): Promise<Response> => handle(async () => {
    if (message.method !== 'POST') return json({ error: 'Method unavailable.' }, 405);
    const secret = settings('PAYMONGO_WEBHOOK_SECRET');
    if (!secret) return json({ error: 'PayMongo test webhook is unavailable.' }, 503);
    const body = new Uint8Array(await message.arrayBuffer());
    if (body.length > 256_000) return json({ error: 'Webhook too large.' }, 413);
    if (!await validSignature(message.headers.get('Paymongo-Signature'), body, secret)) {
      return json({ error: 'Invalid test webhook signature.' }, 401);
    }

    let document: RecordData;
    try {
      document = record(JSON.parse(new TextDecoder().decode(body)));
    } catch {
      return json({ error: 'Invalid webhook body.' }, 400);
    }
    const envelope = record(document.data);
    const event = envelope.type === 'event' ? record(envelope.attributes) : envelope;
    if (event.livemode !== false) return json({ error: 'Expected a test webhook.' }, 400);
    if (event.type !== 'checkout_session.payment.paid') return json({ status: 'ignored' });

    const session = record(event.data);
    const details = record(session.attributes);
    const attemptId = details.reference_number;
    // The PayMongo account may also deliver events for other applications.
    if (typeof attemptId !== 'string' || !uuid.test(attemptId)) return json({ status: 'ignored' });
    const payments = Array.isArray(details.payments) ? details.payments : [];
    const paid = payments.map(record).filter((payment) => record(payment.attributes).status === 'paid');
    const payment = paid[0];
    const amount = record(payment?.attributes).amount;
    if (session.type !== 'checkout_session' || typeof session.id !== 'string' ||
      !checkoutIdPattern.test(session.id) || details.livemode === true || paid.length !== 1 ||
      typeof payment.id !== 'string' || !paymentIdPattern.test(payment.id) ||
      record(payment.attributes).currency !== 'PHP' ||
      typeof amount !== 'number' || !Number.isSafeInteger(amount) || amount <= 0 ||
      amount >= 1_000_000_000) {
      return json({ error: 'Invalid test payment details.' }, 400);
    }

    const eventId = typeof envelope.id === 'string' && /^evt_[a-zA-Z0-9]+$/.test(envelope.id)
      ? envelope.id : payment.id;
    const result = await database(settings, request).rpc<string>('paymongo_confirm_payment', {
      p_event_id: eventId,
      p_attempt_id: attemptId,
      p_checkout_id: session.id,
      p_payment_id: payment.id,
      p_amount_centavos: amount,
    });
    if (result === 'retry') return json({ error: 'Checkout record is being saved.' }, 503);
    if (result === 'mismatch') return json({ error: 'Payment does not match the booking.' }, 409);
    return json({ status: result });
  });
}
