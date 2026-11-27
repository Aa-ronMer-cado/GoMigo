begin;
-- Exercise the historical Maya implementation without allowing new Maya checkouts in the app.
drop trigger if exists stop_new_maya_checkout on payments_private.maya_checkout_attempts;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select no_plan();

insert into auth.users (id, email) values
  ('7e62bea2-0279-4bb6-b96a-1566c1f4ca01', 'maya-traveler@example.test'),
  ('7e62bea2-0279-4bb6-b96a-1566c1f4ca02', 'maya-outsider@example.test');
insert into public.amigo_profiles (id, display_name, description, area, age, gender, rate_centavos)
values ('7e62bea2-0279-4bb6-b96a-1566c1f4ca03', 'Maya fixture', 'Test profile', 'Manila', 35, 'unspecified', 12300);

insert into public.bookings (
  id, request_id, traveler_id, amigo_id, status, payment_status, starts_at, ends_at,
  meeting_label, meeting_lat, meeting_lng, subtotal_centavos, fee_centavos, total_centavos
)
select id, gen_random_uuid(), '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', '7e62bea2-0279-4bb6-b96a-1566c1f4ca03',
  'accepted', payment_status, now() + starts_in, now() + starts_in + interval '1 hour',
  'Test meetup', 14.58, 120.98, 12300, 1230, 13530
from (values
  ('7e62bea2-0279-4bb6-b96a-1566c1f4ca04'::uuid, 'unpaid', interval '1 day'),
  ('7e62bea2-0279-4bb6-b96a-1566c1f4ca05'::uuid, 'unpaid', interval '2 days'),
  ('7e62bea2-0279-4bb6-b96a-1566c1f4ca06'::uuid, 'failed', interval '3 days'),
  ('7e62bea2-0279-4bb6-b96a-1566c1f4ca07'::uuid, 'unpaid', interval '4 days')
) as fixture(id, payment_status, starts_in);
insert into payments_private.checkout_attempts (booking_id, amount_centavos, status, checkout_id, checkout_url)
values ('7e62bea2-0279-4bb6-b96a-1566c1f4ca06', 13530, 'failed', 'cs_mayaLegacy',
  'https://checkout.paymongo.com/fixture');

select ok(not has_function_privilege('authenticated',
  'public.maya_record_payment(uuid,text,text,integer,text,text)', 'EXECUTE'), 'Traveler cannot settle a payment');
select ok(not has_function_privilege('anon', 'public.maya_save_checkout(uuid,text,text)', 'EXECUTE'),
  'Anonymous clients cannot bind external checkout IDs');
select ok(not has_function_privilege('authenticated', 'public.maya_release_uncreated(uuid,boolean)', 'EXECUTE'),
  'Only a trusted service may release an uncreated reservation');

set local role service_role;
select throws_ok($$
  select public.maya_checkout_for_traveler('7e62bea2-0279-4bb6-b96a-1566c1f4ca04',
    '7e62bea2-0279-4bb6-b96a-1566c1f4ca02', true)
$$, 'GM404', 'Booking unavailable', 'Checkout verifies the authenticated booking owner');
select is(public.maya_checkout_for_traveler('7e62bea2-0279-4bb6-b96a-1566c1f4ca04',
  '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', false) ->> 'status', 'unpaid', 'Status lookup leaves checkout unpaid');
select is(public.maya_checkout_for_traveler('7e62bea2-0279-4bb6-b96a-1566c1f4ca06',
  '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', false),
  '{"status":"failed","provider":"paymongo","can_create":false}'::jsonb, 'Legacy state remains readable without its checkout URL');
select throws_ok($$
  select public.maya_checkout_for_traveler('7e62bea2-0279-4bb6-b96a-1566c1f4ca06',
    '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', true)
$$, 'GM409', 'The existing PayMongo test checkout must be resolved first', 'An open legacy checkout blocks Maya');

do $$
begin
  perform set_config('gomigo_test.maya_attempt', public.maya_checkout_for_traveler(
    '7e62bea2-0279-4bb6-b96a-1566c1f4ca04', '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', true
  )::text, true);
end;
$$;
select is(current_setting('gomigo_test.maya_attempt')::jsonb ->> 'can_create', 'true',
  'Fresh reservation authorizes precisely one provider creation');
select is((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'amount_centavos')::int, 13530,
  'Checkout amount comes from the trusted total including the stored fee');
select is(public.maya_checkout_for_traveler('7e62bea2-0279-4bb6-b96a-1566c1f4ca04',
  '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', true) ->> 'can_create', 'false',
  'Retry of an unresolved reservation cannot repeat provider creation');
select is(public.maya_checkout_for_traveler('7e62bea2-0279-4bb6-b96a-1566c1f4ca04',
  '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', false) ->> 'id',
  current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id', 'Retry retains the same merchant reference');

select is(public.maya_record_payment('7e62bea2-0279-4bb6-b96a-1566c1f4ca03',
  '199d1c8a-9892-43a1-8c49-7d293f02dc01', 'paid', 13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc01')
  ->> 'status', 'unmatched', 'An unrelated provider reference cannot touch a booking');
select is(public.maya_record_payment((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc01', 'paid', 13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc01')
  ->> 'status', 'unbound', 'Settlement waits for the verified checkout binding');

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '7e62bea2-0279-4bb6-b96a-1566c1f4ca01';
select throws_ok($$select public.cancel_booking('7e62bea2-0279-4bb6-b96a-1566c1f4ca04')$$,
  'P0001', 'Cancel the open checkout before cancelling the booking.', 'A reservation blocks concurrent Traveler cancellation');
select throws_ok($$select public.cancel_booking('7e62bea2-0279-4bb6-b96a-1566c1f4ca06')$$,
  'P0001', 'Cancel the open checkout before cancelling the booking.', 'A failed but open legacy checkout still blocks cancellation');
reset role;

set local role service_role;
select is(public.maya_save_checkout((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc01', null) ->> 'checkout_url',
  null, 'A verified recovery can bind a checkout without a rediscovered URL');
select is(public.maya_save_checkout((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc01', 'https://payments-web-sandbox.paymaya.com/checkout?id=fixture')
  ->> 'checkout_url', 'https://payments-web-sandbox.paymaya.com/checkout?id=fixture',
  'An original sandbox checkout URL can fill the recovered binding');
select is(public.maya_release_uncreated((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid, true)
  ->> 'status', 'pending', 'A bound checkout can only be resolved by its provider state');
select throws_ok($$
  select public.maya_record_payment((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid,
    '199d1c8a-9892-43a1-8c49-7d293f02dc01', 'paid', 13531, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc01')
$$, 'GM409', 'Payment mismatch', 'A mismatched amount cannot settle an attempt');
select throws_ok($$
  select public.maya_record_payment((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid,
    '199d1c8a-9892-43a1-8c49-7d293f02dc01', 'paid', 13530, 'USD', '199d1c8a-9892-43a1-8c49-7d293f02dc01')
$$, 'GM409', 'Payment mismatch', 'A mismatched currency cannot settle an attempt');
select throws_ok($$
  select public.maya_record_payment((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid,
    '199d1c8a-9892-43a1-8c49-7d293f02dc02', 'paid', 13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc02')
$$, 'GM409', 'Payment mismatch', 'A different provider checkout cannot settle an attempt');
select is(public.maya_record_payment((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc01', 'failed', 13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc01')
  ->> 'status', 'failed', 'Verified terminal failure releases the attempt');

do $$
begin
  perform set_config('gomigo_test.maya_retry', public.maya_checkout_for_traveler(
    '7e62bea2-0279-4bb6-b96a-1566c1f4ca04', '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', true
  )::text, true);
end;
$$;
select ok(current_setting('gomigo_test.maya_retry')::jsonb ->> 'id' <>
  current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id' and
  (current_setting('gomigo_test.maya_retry')::jsonb ->> 'can_create')::boolean,
  'A provider-confirmed failure permits exactly one fresh attempt on explicit retry');
select is(public.maya_record_payment((current_setting('gomigo_test.maya_attempt')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc01', 'cancelled', 13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc01')
  ->> 'status', 'failed', 'A late notification for a terminal attempt cannot alter the retry');
select is(public.maya_save_checkout((current_setting('gomigo_test.maya_retry')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc02', 'https://payments-web-sandbox.maya.ph/checkout?id=retry')
  ->> 'checkout_id', '199d1c8a-9892-43a1-8c49-7d293f02dc02', 'Retry binds to a distinct provider checkout');
select is(public.maya_record_payment((current_setting('gomigo_test.maya_retry')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc02', 'paid', 13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc02')
  ->> 'status', 'paid', 'Verified settlement records the paid status');
select is((select payment_status from public.bookings where id = '7e62bea2-0279-4bb6-b96a-1566c1f4ca04'),
  'paid', 'Checkout and booking settlement write together');
select is(public.maya_record_payment((current_setting('gomigo_test.maya_retry')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc02', 'paid', 13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc02')
  ->> 'paid_at', (select to_jsonb(paid_at) #>> '{}' from payments_private.maya_checkout_attempts
  where checkout_id = '199d1c8a-9892-43a1-8c49-7d293f02dc02'), 'Duplicate success preserves the settlement timestamp');
select is(public.maya_record_payment((current_setting('gomigo_test.maya_retry')::jsonb ->> 'id')::uuid,
  '199d1c8a-9892-43a1-8c49-7d293f02dc02', 'cancelled', 13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc02')
  ->> 'status', 'paid', 'Late cancellation does not downgrade paid');
select is(public.maya_checkout_for_traveler('7e62bea2-0279-4bb6-b96a-1566c1f4ca04',
  '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', true) ->> 'can_create', 'false', 'Paid booking cannot open another checkout');

do $$
begin
  perform set_config('gomigo_test.maya_uncreated', public.maya_checkout_for_traveler(
    '7e62bea2-0279-4bb6-b96a-1566c1f4ca07', '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', true
  ) ->> 'id', true);
end;
$$;
select throws_ok($$
  select public.maya_save_checkout(current_setting('gomigo_test.maya_uncreated')::uuid,
    '199d1c8a-9892-43a1-8c49-7d293f02dc04', 'https://payments-web-sandbox.maya.ph.example.test/checkout')
$$, '23514', null, 'Checkout URL must belong to an exact sandbox host');
select is(public.maya_release_uncreated(current_setting('gomigo_test.maya_uncreated')::uuid, false)
  ->> 'status', 'pending', 'Ambiguous checkout remains reserved during the provider expiry window');
update payments_private.maya_checkout_attempts set created_at = now() - interval '66 minutes'
where id = current_setting('gomigo_test.maya_uncreated')::uuid;
select is(public.maya_release_uncreated(current_setting('gomigo_test.maya_uncreated')::uuid, false)
  ->> 'status', 'cancelled', 'Trusted empty lookup after expiry can release an unbound attempt');
select throws_ok($$
  select public.maya_save_checkout(current_setting('gomigo_test.maya_uncreated')::uuid,
    '199d1c8a-9892-43a1-8c49-7d293f02dc04', null)
$$, 'GM409', 'Checkout mismatch', 'Late binding cannot reopen a released attempt');
select is(public.maya_release_uncreated(
  (public.maya_checkout_for_traveler('7e62bea2-0279-4bb6-b96a-1566c1f4ca07',
    '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', true) ->> 'id')::uuid, true
) ->> 'status', 'cancelled', 'Definitive rejection releases a fresh reservation without waiting');
select is((select payment_status from public.bookings where id = '7e62bea2-0279-4bb6-b96a-1566c1f4ca07'),
  'cancelled', 'Releasing an uncreated attempt updates the linked booking state');

do $$
declare attempt_id uuid;
begin
  attempt_id := (public.maya_checkout_for_traveler(
    '7e62bea2-0279-4bb6-b96a-1566c1f4ca05', '7e62bea2-0279-4bb6-b96a-1566c1f4ca01', true
  ) ->> 'id')::uuid;
  perform public.maya_save_checkout(attempt_id, '199d1c8a-9892-43a1-8c49-7d293f02dc03', null);
  perform public.maya_record_payment(attempt_id, '199d1c8a-9892-43a1-8c49-7d293f02dc03', 'failed',
    13530, 'PHP', '199d1c8a-9892-43a1-8c49-7d293f02dc03');
end;
$$;
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '7e62bea2-0279-4bb6-b96a-1566c1f4ca01';
select is(public.cancel_booking('7e62bea2-0279-4bb6-b96a-1566c1f4ca05') ->> 'status', 'cancelled',
  'A verified terminal Maya failure allows the Traveler to cancel the booking');
reset role;

select * from finish();
rollback;
