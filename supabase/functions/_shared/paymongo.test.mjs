import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';
import { checkoutHandler, webhookHandler } from './paymongo.ts';

const bookingId = '4b24747d-428b-48de-82dc-516909462219';
const travelerId = 'a34a8546-82af-4e54-aa1b-bbd31dc3e39d';
const attemptId = '1a242052-ede0-4365-a2df-0ed2b8044b91';
const webhookSecret = 'fictional-webhook-test-secret';
const checkoutUrl = 'https://checkout.paymongo.com/fixture';
const settings = {
  SUPABASE_URL: 'https://gomigo.example',
  SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_fixture' }),
  PAYMONGO_TEST_SECRET_KEY: 'sk_test_fixture',
  PAYMONGO_WEBHOOK_SECRET: webhookSecret,
  PAYMONGO_RETURN_URL: 'https://gomigo.example/return',
};
const storedAttempt = {
  id: attemptId,
  amount_centavos: 12_300,
  checkout_id: 'cs_fixture',
  checkout_url: checkoutUrl,
  status: 'pending',
  created_at: new Date().toISOString(),
};

function callCheckout(action, authorization = 'Bearer fixturesession') {
  return new Request('https://gomigo.example/paymongo-checkout', {
    method: 'POST',
    headers: authorization ? { Authorization: authorization } : {},
    body: JSON.stringify({ booking_id: bookingId, action, amount_centavos: 1 }),
  });
}

function providerSession(attributes = {}) {
  return Response.json({
    data: {
      id: 'cs_fixture',
      type: 'checkout_session',
      attributes: {
        checkout_url: checkoutUrl,
        livemode: false,
        reference_number: attemptId,
        status: 'active',
        ...attributes,
      },
    },
  });
}

function paidEvent() {
  return {
    data: {
      id: 'evt_fixture',
      type: 'event',
      attributes: {
        type: 'checkout_session.payment.paid',
        livemode: false,
        data: {
          id: 'cs_fixture',
          type: 'checkout_session',
          attributes: {
            reference_number: attemptId,
            payments: [{ id: 'pay_fixture', attributes: { status: 'paid', currency: 'PHP', amount: 12_300 } }],
          },
        },
      },
    },
  };
}

function callWebhook(payload, { alter = false, age = 0, mode = 'te' } = {}) {
  const timestamp = Math.floor(Date.now() / 1000) - age;
  const body = JSON.stringify(payload);
  const signature = createHmac('sha256', webhookSecret).update(`${timestamp}.${body}`).digest('hex');
  return new Request('https://gomigo.example/paymongo-webhook', {
    method: 'POST',
    headers: { 'Paymongo-Signature': `t=${timestamp},${mode}=${signature}` },
    body: alter ? `${body} ` : body,
  });
}

test('rejects unauthenticated callers without contacting Auth, REST or PayMongo', async () => {
  const checkout = checkoutHandler((name) => settings[name], () => assert.fail('Unexpected fetch'));
  const response = await checkout(callCheckout('open', null));
  assert.equal(response.status, 401);
});

test('rejects a missing or other traveler booking before contacting PayMongo', async () => {
  const checkout = checkoutHandler((name) => settings[name], async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: travelerId });
    assert.equal(url, `${settings.SUPABASE_URL}/rest/v1/rpc/paymongo_checkout_for_traveler`);
    assert.equal(options.headers.Authorization, undefined);
    assert.deepEqual(JSON.parse(options.body), {
      p_booking_id: bookingId,
      p_traveler_id: travelerId,
      p_create: false,
    });
    return Response.json({ code: 'GM404' }, { status: 400 });
  });
  const response = await checkout(callCheckout('open'));
  assert.equal(response.status, 404);
});

test('checkout retries reuse the reserved provider key and charge only the server total', async () => {
  let createCalls = 0;
  let attempt = { status: 'unpaid' };
  const checkout = checkoutHandler((name) => settings[name], async (url, options) => {
    if (url.endsWith('/auth/v1/user')) {
      assert.equal(options.headers.Authorization, 'Bearer fixturesession');
      return Response.json({ id: travelerId });
    }
    if (url.endsWith('/paymongo_checkout_for_traveler')) {
      if (JSON.parse(options.body).p_create) {
        attempt = { ...storedAttempt, checkout_id: null, checkout_url: null };
      }
      return Response.json(attempt);
    }
    if (url.endsWith('/paymongo_save_checkout')) {
      assert.deepEqual(JSON.parse(options.body), {
        p_attempt_id: attemptId,
        p_checkout_id: 'cs_fixture',
        p_checkout_url: checkoutUrl,
      });
      attempt = storedAttempt;
      return Response.json(attempt);
    }
    assert.equal(url, 'https://api.paymongo.com/v2/checkout_sessions');
    assert.equal(options.method, 'POST');
    assert.equal(options.headers['Idempotency-Key'], attemptId);
    const attributes = JSON.parse(options.body).data.attributes;
    assert.equal(attributes.reference_number, attemptId);
    assert.equal(attributes.line_items[0].amount, 12_300);
    assert.equal(attributes.line_items[0].currency, 'PHP');
    assert.deepEqual(attributes.payment_method_types, ['card']);
    assert.equal(attributes.pass_on_fees, false);
    createCalls++;
    if (createCalls === 1) return Response.json({}, { status: 503 });
    return providerSession();
  });

  assert.equal((await checkout(callCheckout('open'))).status, 502);
  assert.deepEqual(await (await checkout(callCheckout('open'))).json(), {
    status: 'pending', checkout_url: checkoutUrl,
  });
  assert.equal(createCalls, 2);
});

test('refuses a live key and does not reserve checkout', async () => {
  const checkout = checkoutHandler((name) => name === 'PAYMONGO_TEST_SECRET_KEY'
    ? 'sk_live_fixture' : settings[name], async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: travelerId });
    assert.equal(url, `${settings.SUPABASE_URL}/rest/v1/rpc/paymongo_checkout_for_traveler`);
    assert.equal(JSON.parse(options.body).p_create, false);
    return Response.json({ status: 'unpaid' });
  });
  assert.equal((await checkout(callCheckout('open'))).status, 503);
});

test('a card decline can be retried on the same checkout and a provider expiry cancels it', async () => {
  let attempt = storedAttempt;
  const checkout = checkoutHandler((name) => settings[name], async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: travelerId });
    if (url.endsWith('/paymongo_checkout_for_traveler')) return Response.json(attempt);
    if (url.endsWith('/paymongo_refresh_checkout')) {
      const args = JSON.parse(options.body);
      assert.equal(args.p_attempt_id, attemptId);
      assert.equal(args.p_checkout_id, 'cs_fixture');
      attempt = { ...attempt, status: args.p_status };
      return Response.json(attempt);
    }
    if (url.endsWith('/cs_fixture/expire')) {
      assert.equal(options.method, 'POST');
      return providerSession({ status: 'expired' });
    }
    assert.equal(url, 'https://api.paymongo.com/v1/checkout_sessions/cs_fixture');
    return providerSession({ payment_intent: { attributes: {
      status: 'awaiting_payment_method', last_payment_error: { code: 'failed' },
    } } });
  });
  assert.deepEqual(await (await checkout(callCheckout('status'))).json(), {
    status: 'failed', checkout_url: checkoutUrl,
  });
  assert.deepEqual(await (await checkout(callCheckout('cancel'))).json(), {
    status: 'cancelled', checkout_url: null,
  });
});

test('rejects a provider processing cancellation and waits for the paid webhook after success', async () => {
  let paid = false;
  const checkout = checkoutHandler((name) => settings[name], async (url) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: travelerId });
    if (url.endsWith('/paymongo_checkout_for_traveler')) return Response.json(storedAttempt);
    if (url.endsWith('/cs_fixture/expire')) return Response.json({}, { status: 400 });
    assert.equal(url, 'https://api.paymongo.com/v1/checkout_sessions/cs_fixture');
    return providerSession({ payment_intent: { attributes: { status: paid ? 'succeeded' : 'processing' } } });
  });
  assert.equal((await checkout(callCheckout('cancel'))).status, 409);
  paid = true;
  assert.deepEqual(await (await checkout(callCheckout('status'))).json(), {
    status: 'pending', checkout_url: null,
  });
});

test('rejects tampered, stale and live webhook delivery before contacting the database', async () => {
  const webhook = webhookHandler((name) => settings[name], () => assert.fail('Unexpected fetch'));
  assert.equal((await webhook(callWebhook(paidEvent(), { alter: true }))).status, 401);
  assert.equal((await webhook(callWebhook(paidEvent(), { mode: 'li' }))).status, 401);
  assert.equal((await webhook(callWebhook(paidEvent(), { age: 8 * 86400 }))).status, 401);
  const live = paidEvent();
  live.data.attributes.livemode = true;
  assert.equal((await webhook(callWebhook(live))).status, 400);
  const wrongCurrency = paidEvent();
  wrongCurrency.data.attributes.data.attributes.payments[0].attributes.currency = 'USD';
  assert.equal((await webhook(callWebhook(wrongCurrency))).status, 400);
});

test('the paid webhook preserves correlation keys and acknowledges repeated delivery', async () => {
  let calls = 0;
  const webhook = webhookHandler((name) => settings[name], async (url, options) => {
    assert.equal(url, `${settings.SUPABASE_URL}/rest/v1/rpc/paymongo_confirm_payment`);
    assert.deepEqual(JSON.parse(options.body), {
      p_event_id: calls === 2 ? 'pay_fixture' : 'evt_fixture',
      p_attempt_id: attemptId,
      p_checkout_id: 'cs_fixture',
      p_payment_id: 'pay_fixture',
      p_amount_centavos: 12_300,
    });
    return Response.json(calls++ === 0 ? 'applied' : 'duplicate');
  });
  assert.deepEqual(await (await webhook(callWebhook(paidEvent()))).json(), { status: 'applied' });
  assert.deepEqual(await (await webhook(callWebhook(paidEvent()))).json(), { status: 'duplicate' });
  const alternateEnvelope = { event_type: 'send.webhook', data: paidEvent().data.attributes };
  assert.deepEqual(await (await webhook(callWebhook(alternateEnvelope))).json(), { status: 'duplicate' });
});
