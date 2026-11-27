import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import test from 'node:test';
import { checkoutHandler, webhookHandler } from './maya.ts';

const bookingId = '4b24747d-428b-48de-82dc-516909462219';
const travelerId = 'a34a8546-82af-4e54-aa1b-bbd31dc3e39d';
const attemptId = '1a242052-ede0-4365-a2df-0ed2b8044b91';
const checkoutId = 'ddc4d214-562d-4c20-b662-70e49ea4e720';
const checkoutUrl = 'https://payments-web-sandbox.maya.ph/checkout/fixture';
const sandbox = 'https://pg-sandbox.paymaya.com';
const paymentUrl = `${sandbox}/payments/v1/payments/${checkoutId}`;
const rrnUrl = `${sandbox}/payments/v1/payment-rrns/${attemptId}`;
const accessToken = 'Bearer fixture-session';
const settings = {
  SUPABASE_URL: 'https://gomigo.example',
  SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'sb_secret_fixture' }),
  MAYA_SANDBOX_PUBLIC_KEY: 'pk-fixture',
  MAYA_SANDBOX_SECRET_KEY: 'sk-fixture',
};
const getSetting = (name) => settings[name];
const pending = {
  id: attemptId,
  status: 'pending',
  provider: 'maya',
  amount_centavos: 12345,
  checkout_id: checkoutId,
  checkout_url: checkoutUrl,
  can_create: false,
};
const unpaid = { status: 'unpaid', provider: 'maya', can_create: false };
const unbound = { ...pending, checkout_id: null, checkout_url: null };
const keys = Array.from({ length: 2 }, () => generateKeyPairSync('rsa', { modulusLength: 2048 }));
const publicKeys = keys.map(({ publicKey }) => publicKey.export({ type: 'spki', format: 'der' }).toString('base64'));

function checkoutRequest(action, authorization = accessToken) {
  return new Request('https://gomigo.example/functions/v1/maya-checkout', {
    method: 'POST',
    headers: authorization ? { Authorization: authorization } : {},
    body: JSON.stringify({ booking_id: bookingId, action, amount_centavos: 1 }),
  });
}

function payment(status = 'PENDING_TOKEN', changes = {}) {
  return { id: checkoutId, requestReferenceNumber: attemptId, currency: 'PHP', amount: '123.45', status, ...changes };
}

function webhookRequest({ tampered = false, timestamp = Date.now(), id = checkoutId } = {}) {
  const nonce = 'fixture_nonce';
  const body = {
    id, paymentStatus: 'PAYMENT_SUCCESS',
    fields: { count: 4, empty: '', nil: null, array: ['first', false], skip: {} },
  };
  const canonical = `fields.array.0=first&fields.array.1=false&fields.count=4&id=${id}&paymentStatus=PAYMENT_SUCCESS&nonce=${nonce}`;
  const signature = sign('sha256', Buffer.from(canonical), keys[1].privateKey).toString('hex');
  if (tampered) body.fields.count = 5;
  return new Request('https://gomigo.example/functions/v1/maya-webhook', {
    method: 'POST',
    headers: { 'X-Maya-Webhook-Signature': `nonce=${nonce},v1=${signature}`, 'X-Maya-Webhook-Timestamp': String(timestamp) },
    body: JSON.stringify(body),
  });
}

function authorizedUser(url, options) {
  assert.equal(url, `${settings.SUPABASE_URL}/auth/v1/user`);
  assert.equal(options.headers.Authorization, accessToken);
  return Response.json({ id: travelerId });
}

function expectLookup(args, create) {
  assert.deepEqual(args, { p_booking_id: bookingId, p_traveler_id: travelerId, p_create: create });
}

test('returns 401 before fetching and masks an unrelated booking before Maya is called', async () => {
  const noAuth = checkoutHandler(getSetting, () => assert.fail('No request expected'));
  assert.equal((await noAuth(checkoutRequest('open', null))).status, 401);

  const other = checkoutHandler(getSetting, async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return authorizedUser(url, options);
    assert.equal(url, `${settings.SUPABASE_URL}/rest/v1/rpc/maya_checkout_for_traveler`);
    expectLookup(JSON.parse(options.body), false);
    return Response.json({ code: 'GM404' }, { status: 400 });
  });
  assert.equal((await other(checkoutRequest('open'))).status, 404);
});

test('creates exactly one checkout for concurrent requests and charges the trusted PHP amount', async () => {
  let attempt = unpaid;
  let created = 0;
  let releaseCreate;
  let reachedCreate;
  const heldCreate = new Promise((resolve) => { releaseCreate = resolve; });
  const creating = new Promise((resolve) => { reachedCreate = resolve; });

  const checkout = checkoutHandler(getSetting, async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return authorizedUser(url, options);
    if (url.endsWith('/maya_checkout_for_traveler')) {
      const args = JSON.parse(options.body);
      expectLookup(args, args.p_create);
      if (!args.p_create || attempt.id) return Response.json(attempt);
      attempt = unbound;
      return Response.json({ ...attempt, can_create: true });
    }
    if (url.endsWith('/maya_save_checkout')) {
      assert.deepEqual(JSON.parse(options.body), {
        p_attempt_id: attemptId, p_checkout_id: checkoutId, p_checkout_url: checkoutUrl,
      });
      attempt = pending;
      return Response.json(attempt);
    }
    if (url === rrnUrl) {
      assert.equal(options.headers.Authorization, `Basic ${btoa('sk-fixture:')}`);
      return Response.json([]);
    }
    if (url === paymentUrl) return Response.json(payment());
    assert.equal(url, `${sandbox}/checkout/v1/checkouts`);
    assert.equal(options.method, 'POST');
    assert.equal(options.headers.Authorization, `Basic ${btoa('pk-fixture:')}`);
    const returnUrl = `${settings.SUPABASE_URL}/functions/v1/maya-checkout`;
    assert.deepEqual(JSON.parse(options.body), {
      totalAmount: { value: 123.45, currency: 'PHP' },
      requestReferenceNumber: attemptId,
      redirectUrl: { success: returnUrl, failure: returnUrl, cancel: returnUrl },
    });
    created++;
    reachedCreate();
    await heldCreate;
    return Response.json({ checkoutId, redirectUrl: checkoutUrl });
  });

  const first = checkout(checkoutRequest('open'));
  await creating;
  try {
    assert.deepEqual(await (await checkout(checkoutRequest('open'))).json(), {
      provider: 'maya', status: 'pending', checkout_url: null,
    });
  } finally {
    releaseCreate();
  }
  const expected = { provider: 'maya', status: 'pending', checkout_url: checkoutUrl };
  assert.deepEqual(await (await first).json(), expected);
  assert.deepEqual(await (await checkout(checkoutRequest('open'))).json(), expected);
  assert.equal(created, 1);
});

test('reconciles an uncertain create by exact reference without creating again or inventing a URL', async () => {
  let bound = false;
  const checkout = checkoutHandler(getSetting, async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return authorizedUser(url, options);
    if (url.endsWith('/maya_checkout_for_traveler')) return Response.json(unbound);
    if (url.endsWith('/maya_save_checkout')) {
      assert.deepEqual(JSON.parse(options.body), {
        p_attempt_id: attemptId, p_checkout_id: checkoutId, p_checkout_url: null,
      });
      bound = true;
      return Response.json({ ...pending, checkout_url: null });
    }
    assert.equal(url, rrnUrl);
    return Response.json([payment()]);
  });
  assert.deepEqual(await (await checkout(checkoutRequest('open'))).json(), {
    provider: 'maya', status: 'pending', checkout_url: null,
  });
  assert.equal(bound, true);
});

test('never returns a live provider redirect or exposes a legacy checkout URL', async () => {
  let savedId = false;
  const rejectedRedirect = checkoutHandler(getSetting, async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return authorizedUser(url, options);
    if (url.endsWith('/maya_checkout_for_traveler')) {
      return Response.json(JSON.parse(options.body).p_create ? { ...unbound, can_create: true } : unpaid);
    }
    if (url.endsWith('/maya_save_checkout')) {
      assert.deepEqual(JSON.parse(options.body), {
        p_attempt_id: attemptId, p_checkout_id: checkoutId, p_checkout_url: null,
      });
      savedId = true;
      return Response.json({ ...pending, checkout_url: null });
    }
    assert.equal(url, `${sandbox}/checkout/v1/checkouts`);
    return Response.json({ checkoutId, redirectUrl: 'https://payments.maya.ph/checkout/fixture' });
  });
  assert.equal((await rejectedRedirect(checkoutRequest('open'))).status, 502);
  assert.equal(savedId, true);

  const legacy = checkoutHandler(getSetting, async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return authorizedUser(url, options);
    assert.equal(url, `${settings.SUPABASE_URL}/rest/v1/rpc/maya_checkout_for_traveler`);
    expectLookup(JSON.parse(options.body), false);
    return Response.json({ ...pending, provider: 'paymongo' });
  });
  assert.deepEqual(await (await legacy(checkoutRequest('open'))).json(), {
    provider: 'paymongo', status: 'pending', checkout_url: null,
  });
});

test('keeps ambiguous checkout claims until expiry but releases a definitive provider rejection', async () => {
  let lookup = unpaid;
  let providerStatus = 502;
  let lookupError = 'unexpected';
  const releases = [];
  const checkout = checkoutHandler(getSetting, async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return authorizedUser(url, options);
    if (url.endsWith('/maya_checkout_for_traveler')) {
      if (JSON.parse(options.body).p_create) {
        lookup = { ...unbound, created_at: new Date().toISOString() };
        return Response.json({ ...lookup, can_create: true });
      }
      return Response.json(lookup);
    }
    if (url.endsWith('/maya_release_uncreated')) {
      const args = JSON.parse(options.body);
      assert.equal(args.p_attempt_id, attemptId);
      releases.push(args.p_definitive);
      lookup = { ...lookup, status: 'cancelled' };
      return Response.json(lookup);
    }
    if (url === rrnUrl) return Response.json({ code: lookupError }, { status: 404 });
    assert.equal(url, `${sandbox}/checkout/v1/checkouts`);
    return Response.json({}, { status: providerStatus });
  });

  assert.equal((await checkout(checkoutRequest('open'))).status, 502);
  assert.equal((await checkout(checkoutRequest('status'))).status, 502);
  lookupError = 'PY0009';
  assert.equal((await (await checkout(checkoutRequest('status'))).json()).status, 'pending');
  assert.deepEqual(releases, []);
  lookup.created_at = new Date(Date.now() - 66 * 60_000).toISOString();
  assert.equal((await (await checkout(checkoutRequest('status'))).json()).status, 'cancelled');
  providerStatus = 401;
  assert.equal((await checkout(checkoutRequest('open'))).status, 502);
  assert.deepEqual(releases, [false, true]);
});

test('cancels only when the canonical Maya lookup confirms a valid final state', async () => {
  let cancelled = false;
  let requests = 0;
  const checkout = checkoutHandler(getSetting, async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return authorizedUser(url, options);
    if (url.endsWith('/maya_checkout_for_traveler')) return Response.json(pending);
    if (url.endsWith('/maya_record_payment')) {
      assert.deepEqual(JSON.parse(options.body), {
        p_attempt_id: attemptId, p_checkout_id: checkoutId, p_status: 'cancelled',
        p_amount_centavos: 12345, p_currency: 'PHP', p_payment_id: checkoutId,
      });
      return Response.json({ ...pending, status: 'cancelled' });
    }
    if (url === `${paymentUrl}/cancel`) {
      assert.equal(options.method, 'POST');
      requests++;
      return Response.json({ paymentStatus: 'PAYMENT_CANCELLED' });
    }
    assert.equal(url, paymentUrl);
    return Response.json(payment(cancelled ? 'PAYMENT_CANCELLED' : 'PENDING_TOKEN'));
  });

  assert.equal((await checkout(checkoutRequest('cancel'))).status, 409);
  cancelled = true;
  assert.deepEqual(await (await checkout(checkoutRequest('cancel'))).json(), {
    provider: 'maya', status: 'cancelled', checkout_url: null,
  });
  assert.equal(requests, 1);
});

test('status rejects canonical reference and centavo mismatches before a database write', async () => {
  let changes = { amount: '123.44' };
  const checkout = checkoutHandler(getSetting, async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return authorizedUser(url, options);
    if (url.endsWith('/maya_checkout_for_traveler')) return Response.json(pending);
    assert.equal(url, paymentUrl);
    return Response.json(payment('PAYMENT_SUCCESS', changes));
  });
  assert.equal((await checkout(checkoutRequest('status'))).status, 409);
  changes = { requestReferenceNumber: bookingId };
  assert.equal((await checkout(checkoutRequest('status'))).status, 409);
});

test('a tampered, stale or unsigned webhook never reaches the provider', async () => {
  const webhook = webhookHandler(getSetting, () => assert.fail('No request expected'), publicKeys);
  assert.equal((await webhook(webhookRequest({ tampered: true }))).status, 401);
  assert.equal((await webhook(webhookRequest({ timestamp: Date.now() - 600_000 }))).status, 401);
  const unsigned = new Request('https://gomigo.example/maya-webhook', { method: 'POST', body: '{}' });
  assert.equal((await webhook(unsigned)).status, 401);
});

test('second signing key verifies and a replay uses canonical Maya status, never the webhook claim', async () => {
  let calls = 0;
  const webhook = webhookHandler(getSetting, async (url, options) => {
    if (url === paymentUrl) {
      assert.equal(options.headers.Authorization, `Basic ${btoa('sk-fixture:')}`);
      return Response.json(payment('PAYMENT_FAILED'));
    }
    assert.equal(url, `${settings.SUPABASE_URL}/rest/v1/rpc/maya_record_payment`);
    assert.deepEqual(JSON.parse(options.body), {
      p_attempt_id: attemptId, p_checkout_id: checkoutId, p_status: 'failed',
      p_amount_centavos: 12345, p_currency: 'PHP', p_payment_id: checkoutId,
    });
    calls++;
    return Response.json({ ...pending, status: 'failed' });
  }, publicKeys);
  assert.deepEqual(await (await webhook(webhookRequest())).json(), { status: 'failed' });
  assert.deepEqual(await (await webhook(webhookRequest())).json(), { status: 'failed' });
  assert.equal(calls, 2);
});

test('signed success binds the canonical ID, merchant reference, currency and amount before settling', async () => {
  let fixture = payment('PAYMENT_SUCCESS', { id: bookingId });
  let storedResult = { status: 'unbound' };
  const webhook = webhookHandler(getSetting, async (url, options) => {
    if (url === paymentUrl) return Response.json(fixture);
    assert.equal(url, `${settings.SUPABASE_URL}/rest/v1/rpc/maya_record_payment`);
    assert.deepEqual(JSON.parse(options.body), {
      p_attempt_id: attemptId, p_checkout_id: checkoutId, p_status: 'paid',
      p_amount_centavos: 12345, p_currency: 'PHP', p_payment_id: checkoutId,
    });
    return Response.json(storedResult);
  }, publicKeys);
  assert.equal((await webhook(webhookRequest())).status, 502);
  fixture = payment('PAYMENT_SUCCESS', { currency: 'USD' });
  assert.equal((await webhook(webhookRequest())).status, 502);
  fixture = payment('PAYMENT_SUCCESS');
  assert.equal((await webhook(webhookRequest())).status, 503);
  storedResult = { ...pending, status: 'paid' };
  assert.deepEqual(await (await webhook(webhookRequest())).json(), { status: 'paid' });
});
