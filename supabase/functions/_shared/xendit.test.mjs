import assert from 'node:assert/strict';
import test from 'node:test';
import { checkoutHandler, webhookHandler } from './xendit.ts';

const booking = '4b24747d-428b-48de-82dc-516909462219';
const user = 'a34a8546-82af-4e54-aa1b-bbd31dc3e39d';
const attempt = '1a242052-ede0-4365-a2df-0ed2b8044b91';
const sessionId = 'ps-661f87c614802d6c402cd82d';
const requestId = 'pr-8877c08a-740d-4153-9816-3d744ed197a5';
const settings = {
  SUPABASE_URL: 'https://gomigo.example',
  SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_fixture' }),
  XENDIT_TEST_SECRET_KEY: 'xnd_development_fixture',
  XENDIT_WEBHOOK_TOKEN: 'webhook-fixture',
};
const get = (key) => settings[key];
const active = { id: attempt, provider: 'xendit', status: 'pending', amount_centavos: 12345,
  checkout_id: sessionId, checkout_url: 'https://dev.xen.to/fixture', can_create: false };
const session = (changes = {}) => ({ payment_session_id: sessionId, reference_id: attempt,
  amount: 123.45, currency: 'PHP', country: 'PH', session_type: 'PAY', mode: 'PAYMENT_LINK',
  status: 'ACTIVE', payment_link_url: 'https://dev.xen.to/fixture', ...changes });
const payment = (changes = {}) => ({ payment_request_id: requestId, request_amount: 123.45,
  currency: 'PHP', country: 'PH', capture_method: 'AUTOMATIC', status: 'SUCCEEDED', ...changes });
const input = (action, authorization = 'Bearer test-session') => new Request('https://gomigo.example/xendit-checkout', {
  method: 'POST', headers: authorization ? { Authorization: authorization } : {}, body: JSON.stringify({ booking_id: booking, action }),
});
const webhook = (token = 'webhook-fixture') => new Request('https://gomigo.example/xendit-webhook', {
  method: 'POST', headers: { 'x-callback-token': token },
  body: JSON.stringify({ event: 'payment_session.completed', data: { payment_session_id: sessionId } }),
});

test('creates only one checkout using the trusted booking amount', async () => {
  let lookups = 0;
  const handler = checkoutHandler(get, async (url, options = {}) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: user });
    if (url.endsWith('/xendit_checkout_for_traveler')) {
      const args = JSON.parse(options.body);
      assert.equal(args.p_traveler_id, user);
      lookups++;
      return Response.json(args.p_create ? { ...active, checkout_id: null, checkout_url: null, can_create: true }
        : { provider: 'xendit', status: 'unpaid', can_create: false });
    }
    if (url === 'https://api.xendit.co/sessions') {
      const body = JSON.parse(options.body);
      assert.equal(body.reference_id, attempt);
      assert.equal(body.amount, 123.45);
      assert.equal(body.capture_method, 'AUTOMATIC');
      return Response.json(session());
    }
    if (url.endsWith('/xendit_bind_checkout')) {
      assert.equal(JSON.parse(options.body).p_amount_centavos, 12345);
      return Response.json(active);
    }
    assert.fail(`Unexpected endpoint ${url}`);
  });
  assert.deepEqual(await (await handler(input('open'))).json(), {
    provider: 'xendit', status: 'pending', checkout_url: 'https://dev.xen.to/fixture',
  });
  assert.equal(lookups, 2);
});

test('rejects anonymous access and live Xendit keys', async () => {
  const unauthorized = checkoutHandler(get, async () => assert.fail('No backend call expected'));
  assert.equal((await unauthorized(input('open', null))).status, 401);
  const live = checkoutHandler((key) => key === 'XENDIT_TEST_SECRET_KEY' ? 'xnd_production_fixture' : get(key), async (url) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: user });
    if (url.endsWith('/xendit_checkout_for_traveler')) return Response.json({ provider: 'xendit', status: 'unpaid' });
    assert.fail('No provider request expected');
  });
  assert.equal((await live(input('open'))).status, 503);
});

test('forbidden test checkout releases its reservation and a successful retry is reused', async () => {
  let status = 'unpaid';
  let creates = 0;
  let releases = 0;
  const handler = checkoutHandler(get, async (url, options = {}) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: user });
    if (url.endsWith('/xendit_checkout_for_traveler')) {
      if (status === 'pending') return Response.json(active);
      if (!JSON.parse(options.body).p_create) {
        return Response.json({ provider: 'xendit', status });
      }
      return Response.json({ ...active, checkout_id: null, checkout_url: null, can_create: true });
    }
    if (url === 'https://api.xendit.co/sessions') {
      creates++;
      return creates === 1
        ? Response.json({ error_code: 'REQUEST_FORBIDDEN_ERROR', message: 'fixture detail' }, { status: 403 })
        : Response.json(session());
    }
    if (url.endsWith('/xendit_release_rejected')) {
      assert.equal(JSON.parse(options.body).p_attempt_id, attempt);
      releases++;
      status = 'cancelled';
      return Response.json(null);
    }
    if (url.endsWith('/xendit_bind_checkout')) {
      status = 'pending';
      return Response.json(active);
    }
    if (url.endsWith(`/sessions/${sessionId}`)) return Response.json(session());
    assert.fail(`Unexpected endpoint ${url}`);
  });
  const forbidden = await handler(input('open'));
  assert.equal(forbidden.status, 503);
  assert.equal((await forbidden.json()).code, 'TEST_CHECKOUT_SETUP');
  assert.equal(releases, 1);
  assert.equal((await (await handler(input('open'))).json()).checkout_url, active.checkout_url);
  assert.equal((await (await handler(input('open'))).json()).checkout_url, active.checkout_url);
  assert.equal(creates, 2);
});

test('checks canonical payment status before settling and rejects amount mismatches', async () => {
  let amount = 123.45;
  let writes = 0;
  const handler = checkoutHandler(get, async (url, options = {}) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: user });
    if (url.endsWith('/xendit_checkout_for_traveler')) return Response.json(active);
    if (url.endsWith(`/sessions/${sessionId}`)) return Response.json(session({ status: 'COMPLETED', payment_request_id: requestId }));
    if (url.endsWith(`/v3/payment_requests/${requestId}`)) return Response.json(payment({ request_amount: amount }));
    if (url.endsWith('/xendit_record_payment')) {
      writes++;
      assert.equal(JSON.parse(options.body).p_status, 'paid');
      return Response.json({ ...active, status: 'paid' });
    }
    assert.fail(`Unexpected endpoint ${url}`);
  });
  amount = 123.44;
  assert.equal((await handler(input('status'))).status, 409);
  assert.equal(writes, 0);
  amount = 123.45;
  assert.equal((await (await handler(input('status'))).json()).status, 'paid');
  assert.equal(writes, 1);
});

test('requires a valid callback token and confirms provider data before recording', async () => {
  let writes = 0;
  const handler = webhookHandler(get, async (url) => {
    if (url.endsWith(`/sessions/${sessionId}`)) return Response.json(session({ status: 'COMPLETED', payment_request_id: requestId }));
    if (url.endsWith('/xendit_bind_checkout')) return Response.json(active);
    if (url.endsWith(`/v3/payment_requests/${requestId}`)) return Response.json(payment());
    if (url.endsWith('/xendit_record_payment')) { writes++; return Response.json({ ...active, status: 'paid' }); }
    assert.fail(`Unexpected endpoint ${url}`);
  });
  assert.equal((await handler(webhook('wrong'))).status, 401);
  assert.equal(writes, 0);
  assert.equal((await (await handler(webhook())).json()).status, 'paid');
  assert.equal(writes, 1);
});

test('acknowledges the Xendit dashboard samples without changing payments', async () => {
  const handler = webhookHandler(get, async () => assert.fail('Sample must not call provider or database'));
  const sample = { event: 'payment_session.completed', created: '2020-04-20T16:25:52Z',
    data: { id: 'ps-579c8d61f23fa4ca35e52da4', reference_id: 'test_session',
      session_type: 'SAVE', country: 'ID', currency: 'IDR' } };
  const request = (body, token = 'webhook-fixture') => new Request('https://gomigo.example/xendit-webhook', {
    method: 'POST', headers: { 'x-callback-token': token }, body: JSON.stringify(body),
  });
  assert.equal((await handler(request(sample, 'wrong'))).status, 401);
  for (const event of ['payment_session.completed', 'payment_session.expired']) {
    const result = await handler(request({ ...sample, event }));
    assert.equal(result.status, 200);
    assert.equal((await result.json()).status, 'dashboard_test');
  }
});

test('accepts an id callback but still verifies the session with Xendit', async () => {
  let writes = 0;
  const handler = webhookHandler(get, async (url) => {
    if (url.endsWith(`/sessions/${sessionId}`)) return Response.json(session({ status: 'EXPIRED' }));
    if (url.endsWith('/xendit_bind_checkout')) return Response.json(active);
    if (url.endsWith('/xendit_record_payment')) { writes++; return Response.json({ ...active, status: 'cancelled' }); }
    assert.fail(`Unexpected endpoint ${url}`);
  });
  const req = new Request('https://gomigo.example/xendit-webhook', { method: 'POST',
    headers: { 'x-callback-token': 'webhook-fixture' },
    body: JSON.stringify({ event: 'payment_session.expired', data: { id: sessionId } }) });
  assert.equal((await (await handler(req)).json()).status, 'cancelled');
  assert.equal(writes, 1);
});

test('does not release an ambiguous checkout or pretend cancellation succeeded', async () => {
  const handler = checkoutHandler(get, async (url) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: user });
    if (url.endsWith('/xendit_checkout_for_traveler')) return Response.json({ ...active, checkout_id: null, checkout_url: null });
    assert.fail(`Unexpected endpoint ${url}`);
  });
  assert.equal((await handler(input('cancel'))).status, 409);
  assert.equal((await handler(input('open'))).status, 409);
});
