import { cors, database, handle, json, PaymentError, record, secureUrl, uuid, type Fetch, type RecordData, type Settings } from './payment_http.ts';

type Attempt = {
  id: string | null;
  amount_centavos: number;
  checkout_id: string | null;
  checkout_url: string | null;
  status: 'unpaid' | 'pending' | 'failed' | 'cancelled' | 'paid';
  provider: 'xendit' | 'maya' | 'paymongo';
  can_create: boolean;
};
const sessionIdPattern = /^ps-[a-zA-Z0-9]{24}$/;
const requestIdPattern = /^pr-[0-9a-f-]{36}$/i;
const checkoutHosts = new Set(['checkout-staging.xendit.co', 'dev.xen.to']);

function checkoutUrl(value: unknown): string | null {
  const url = secureUrl(value);
  return url && url.port === '' && checkoutHosts.has(url.hostname) ? url.href : null;
}

function response(attempt: Attempt): Response {
  return json({ provider: attempt.provider, status: attempt.status,
    checkout_url: attempt.provider === 'xendit' && attempt.status === 'pending' ? checkoutUrl(attempt.checkout_url) : null });
}

function provider(settings: Settings, request: Fetch) {
  const key = settings('XENDIT_TEST_SECRET_KEY');
  if (!key?.startsWith('xnd_development_') || !settings('XENDIT_WEBHOOK_TOKEN')) {
    throw new PaymentError(503, 'Xendit test checkout is unavailable.');
  }
  return async (path: string, options: RequestInit = {}) => {
    const result = await request(`https://api.xendit.co${path}`, {
      ...options,
      headers: { Authorization: `Basic ${btoa(`${key}:`)}`, 'Content-Type': 'application/json', 'api-version': '2024-11-11' },
      redirect: 'error', signal: AbortSignal.timeout(12_000),
    });
    return result;
  };
}

function cents(value: unknown): number | null {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value));
  if (!match) return null;
  const amount = Number(match[1]) * 100 + Number((match[2] ?? '').padEnd(2, '0'));
  return Number.isSafeInteger(amount) && amount > 0 ? amount : null;
}

function verifiedSession(data: RecordData, expectedId?: string) {
  const id = data.payment_session_id;
  const reference = data.reference_id;
  const amount = cents(data.amount);
  if (typeof id !== 'string' || !sessionIdPattern.test(id) || (expectedId && id !== expectedId) ||
    typeof reference !== 'string' || !uuid.test(reference) || !amount || data.currency !== 'PHP' ||
    data.country !== 'PH' || data.session_type !== 'PAY' || data.mode !== 'PAYMENT_LINK' ||
    (data.capture_method != null && data.capture_method !== 'AUTOMATIC')) {
    throw new PaymentError(502, 'Xendit returned unexpected test checkout details.');
  }
  return { id, reference, amount, status: data.status, url: checkoutUrl(data.payment_link_url),
    requestId: data.payment_request_id ?? data.latest_payment_request_id };
}

async function readProvider(result: Response): Promise<RecordData> {
  if (!result.ok) throw new PaymentError(502, 'Xendit could not verify the test checkout.');
  return record(await result.json());
}

async function settleSession(db: ReturnType<typeof database>, send: ReturnType<typeof provider>, session: ReturnType<typeof verifiedSession>) {
  let status: 'paid' | 'cancelled' | null = null;
  if (session.status === 'COMPLETED' || ((session.status === 'EXPIRED' || session.status === 'CANCELED') && session.requestId)) {
    if (typeof session.requestId !== 'string' || !requestIdPattern.test(session.requestId)) {
      throw new PaymentError(503, 'Xendit is still verifying this payment.');
    }
    const payment = await readProvider(await send(`/v3/payment_requests/${session.requestId}`));
    if (payment.payment_request_id !== session.requestId || cents(payment.request_amount) !== session.amount ||
      payment.currency !== 'PHP' || payment.country !== 'PH' || payment.capture_method !== 'AUTOMATIC') {
      throw new PaymentError(409, 'Payment details do not match this checkout.');
    }
    if (payment.status === 'SUCCEEDED') status = 'paid';
    else if ((session.status === 'EXPIRED' || session.status === 'CANCELED') &&
      ['CANCELED', 'EXPIRED', 'FAILED'].includes(String(payment.status))) status = 'cancelled';
  } else if (session.status === 'EXPIRED' || session.status === 'CANCELED') {
    status = 'cancelled';
  }
  if (!status) return null;
  return await db.rpc<Attempt | { status: 'unmatched' }>('xendit_record_payment', {
    p_attempt_id: session.reference, p_checkout_id: session.id, p_status: status,
    p_amount_centavos: session.amount, p_currency: 'PHP',
  });
}

export function checkoutHandler(settings: Settings, request: Fetch = fetch) {
  return (message: Request): Promise<Response> => handle(async () => {
    if (message.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (message.method === 'GET') return new Response('Return to GoMigo to check your Xendit test payment.', { headers: { 'Cache-Control': 'no-store' } });
    if (message.method !== 'POST') return json({ error: 'Method unavailable.' }, 405);
    const input = record(await message.json().catch(() => null));
    const bookingId = input.booking_id;
    const action = input.action ?? 'open';
    if (typeof bookingId !== 'string' || !uuid.test(bookingId) || !['open', 'status', 'cancel'].includes(String(action))) {
      return json({ error: 'Enter a booking ID and a supported action.' }, 400);
    }
    const db = database(settings, request);
    const travelerId = await db.travelerId(message.headers.get('Authorization'));
    const lookup = (create: boolean) => db.rpc<Attempt>('xendit_checkout_for_traveler', {
      p_booking_id: bookingId, p_traveler_id: travelerId, p_create: create,
    });
    let attempt = await lookup(false);
    if (attempt.provider !== 'xendit' || attempt.status === 'paid') return response(attempt);
    if (attempt.status !== 'pending' && action !== 'open') return response(attempt);
    const send = provider(settings, request);
    if (attempt.status !== 'pending') {
      const project = secureUrl(settings('SUPABASE_URL'));
      if (!project) throw new PaymentError(503, 'Xendit test checkout is unavailable.');
      const returnUrl = new URL('/functions/v1/xendit-checkout', project).href;
      attempt = await lookup(true);
      if (attempt.can_create && attempt.id) {
        // A timed-out creation remains reserved until a verified webhook or manual reconciliation.
        const createdResponse = await send('/sessions', { method: 'POST', body: JSON.stringify({
          reference_id: attempt.id, session_type: 'PAY', mode: 'PAYMENT_LINK', amount: attempt.amount_centavos / 100,
          currency: 'PHP', country: 'PH', capture_method: 'AUTOMATIC', allow_save_payment_method: 'DISABLED',
          success_return_url: returnUrl, cancel_return_url: returnUrl,
        }) });
        const definitiveErrors = new Set(['API_VALIDATION_ERROR', 'INVALID_AMOUNT', 'INVALID_CURRENCY', 'INVALID_COUNTRY', 'MISSING_CUSTOMER', 'INVALID_URL', 'INVALID_API_KEY']);
        const rejection = [400, 422].includes(createdResponse.status) ? record(await createdResponse.clone().json().catch(() => null)) : {};
        if ([401, 403].includes(createdResponse.status) || definitiveErrors.has(String(rejection.error_code))) {
          await db.rpc('xendit_release_rejected', { p_attempt_id: attempt.id });
          throw new PaymentError(503, 'Xendit rejected the test checkout. Check the setup and try again.');
        }
        const session = verifiedSession(await readProvider(createdResponse));
        if (session.reference !== attempt.id || session.amount !== attempt.amount_centavos || !session.url || session.status !== 'ACTIVE') {
          throw new PaymentError(409, 'Xendit checkout needs reconciliation.');
        }
        attempt = await db.rpc<Attempt>('xendit_bind_checkout', { p_attempt_id: attempt.id, p_checkout_id: session.id, p_checkout_url: session.url, p_amount_centavos: session.amount });
        return response(attempt);
      }
    }
    if (attempt.status !== 'pending' || !attempt.id) return response(attempt);
    if (!attempt.checkout_id) throw new PaymentError(409, 'Test checkout is awaiting reconciliation. Contact support.');
    if (action === 'cancel') await send(`/sessions/${attempt.checkout_id}/cancel`, { method: 'POST' }).then((res) => res.body?.cancel()).catch(() => undefined);
    const session = verifiedSession(await readProvider(await send(`/sessions/${attempt.checkout_id}`)), attempt.checkout_id);
    if (session.reference !== attempt.id || session.amount !== attempt.amount_centavos) throw new PaymentError(409, 'Payment details do not match this booking.');
    const result = await settleSession(db, send, session);
    if (result && 'checkout_id' in result) return response(result);
    if (action === 'cancel') throw new PaymentError(409, 'Cancellation is not yet confirmed. Refresh payment status.');
    return response(attempt);
  });
}

async function validToken(actual: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const a = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(actual)));
  const b = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(expected)));
  return a.reduce((difference, value, index) => difference | (value ^ b[index]), 0) === 0;
}

export function webhookHandler(settings: Settings, request: Fetch = fetch) {
  return (message: Request): Promise<Response> => handle(async () => {
    if (message.method !== 'POST') return json({ error: 'Method unavailable.' }, 405);
    const token = settings('XENDIT_WEBHOOK_TOKEN');
    if (!token) throw new PaymentError(503, 'Xendit webhook is unavailable.');
    if (!await validToken(message.headers.get('x-callback-token') ?? '', token)) return json({ error: 'Invalid webhook token.' }, 401);
    const body = await message.text();
    if (body.length > 256_000) return json({ error: 'Webhook too large.' }, 413);
    const event = record(JSON.parse(body));
    if (event.event !== 'payment_session.completed' && event.event !== 'payment_session.expired') return json({ status: 'ignored' });
    const data = record(event.data);
    // Xendit's dashboard sends a fixed example unrelated to any actual checkout.
    // Acknowledge only that exact sample, without looking up or changing payments.
    if (data.id === 'ps-579c8d61f23fa4ca35e52da4' && data.reference_id === 'test_session' &&
      data.session_type === 'SAVE' && data.country === 'ID' && data.currency === 'IDR' &&
      event.created === '2020-04-20T16:25:52Z') return json({ status: 'dashboard_test' });
    // Current API documentation uses payment_session_id; some callbacks use id.
    const id = data.payment_session_id ?? data.id;
    if (typeof id !== 'string' || !sessionIdPattern.test(id)) return json({ error: 'Invalid session.' }, 400);
    const send = provider(settings, request);
    const session = verifiedSession(await readProvider(await send(`/sessions/${id}`)), id);
    const db = database(settings, request);
    await db.rpc('xendit_bind_checkout', { p_attempt_id: session.reference, p_checkout_id: session.id, p_checkout_url: session.url, p_amount_centavos: session.amount });
    const result = await settleSession(db, send, session);
    if (!result) return json({ error: 'Payment is still being verified.' }, 503);
    return json({ status: result.status });
  });
}
