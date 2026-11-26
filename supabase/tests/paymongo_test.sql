begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(16);

insert into auth.users (id, email) values
  ('8fac1c77-19f3-41d3-ad97-8fd118d79727', 'payment-traveler@example.test'),
  ('8fac1c77-19f3-41d3-ad97-8fd118d79728', 'payment-outsider@example.test');

insert into public.amigo_profiles (id, display_name, description, area, age, gender, rate_centavos, verified, is_test)
values ('8fac1c77-19f3-41d3-ad97-8fd118d79729', 'Payment fixture', 'Test profile', 'Manila', 35, 'unspecified', 12300, true, true);

insert into public.bookings (id, request_id, traveler_id, amigo_id, status, starts_at, ends_at,
  meeting_label, meeting_lat, meeting_lng, subtotal_centavos, fee_centavos, total_centavos)
values (
  '8fac1c77-19f3-41d3-ad97-8fd118d79730', gen_random_uuid(),
  '8fac1c77-19f3-41d3-ad97-8fd118d79727', '8fac1c77-19f3-41d3-ad97-8fd118d79729',
  'accepted', now() + interval '1 day', now() + interval '25 hours', 'Test meetup', 14.58, 120.98,
  12300, 1230, 13530
);

select ok(not has_function_privilege('authenticated',
  'public.paymongo_confirm_payment(text,uuid,text,text,integer)', 'EXECUTE'), 'Traveler cannot confirm payments');
select ok(not has_function_privilege('anon',
  'public.paymongo_checkout_for_traveler(uuid,uuid,boolean)', 'EXECUTE'), 'Anonymous caller cannot reserve checkout');
select ok(not has_schema_privilege('authenticated', 'payments_private', 'USAGE'), 'Payment URLs and ledger are private');
select ok(has_function_privilege('service_role',
  'public.paymongo_confirm_payment(text,uuid,text,text,integer)', 'EXECUTE'), 'Trusted backend can confirm payments');

set local role service_role;
do $$
begin
  if public.paymongo_checkout_for_traveler(
    '8fac1c77-19f3-41d3-ad97-8fd118d79730', '8fac1c77-19f3-41d3-ad97-8fd118d79727', false
  ) ->> 'status' is distinct from 'unpaid' then
    raise exception 'Trusted backend could not inspect the booking';
  end if;
end;
$$;
reset role;

select throws_ok($test$
  select public.paymongo_checkout_for_traveler(
    '8fac1c77-19f3-41d3-ad97-8fd118d79730', '8fac1c77-19f3-41d3-ad97-8fd118d79728', true)
$test$, 'GM404', 'Booking unavailable', 'Checkout cannot reserve somebody else’s booking');

select is(public.paymongo_checkout_for_traveler(
  '8fac1c77-19f3-41d3-ad97-8fd118d79730', '8fac1c77-19f3-41d3-ad97-8fd118d79727', false
) ->> 'status', 'unpaid', 'Viewing status does not create a checkout');

select is((public.paymongo_checkout_for_traveler(
  '8fac1c77-19f3-41d3-ad97-8fd118d79730', '8fac1c77-19f3-41d3-ad97-8fd118d79727', true
) ->> 'amount_centavos')::int, 13530, 'Reservation uses the trusted booking total');

select is(public.paymongo_checkout_for_traveler(
  '8fac1c77-19f3-41d3-ad97-8fd118d79730', '8fac1c77-19f3-41d3-ad97-8fd118d79727', true
) ->> 'id', (select id::text from payments_private.checkout_attempts
  where booking_id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'), 'Creation retries reuse the same reservation');

select is(public.paymongo_save_checkout(
  (select id from payments_private.checkout_attempts where booking_id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'),
  'cs_fixture', 'https://checkout.paymongo.com/fixture'
) ->> 'checkout_id', 'cs_fixture', 'Saves the provider checkout before handing the URL to the Traveler');

select is(public.paymongo_confirm_payment('evt_wrong',
  (select id from payments_private.checkout_attempts where booking_id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'),
  'cs_fixture', 'pay_wrong', 13531), 'mismatch', 'Rejects a signed payment with the wrong amount');

select is(public.paymongo_confirm_payment('evt_wrong',
  (select id from payments_private.checkout_attempts where booking_id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'),
  'cs_wrong', 'pay_wrong', 13530), 'mismatch', 'Rejects a payment for a different checkout');

select is(public.paymongo_refresh_checkout(
  (select id from payments_private.checkout_attempts where booking_id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'),
  'cs_fixture', 'failed') ->> 'status', 'failed', 'Records a provider decline');

select is(public.paymongo_confirm_payment('evt_fixture',
  (select id from payments_private.checkout_attempts where booking_id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'),
  'cs_fixture', 'pay_fixture', 13530), 'applied', 'A successful retry records payment');

select is(public.paymongo_confirm_payment('evt_fixture',
  (select id from payments_private.checkout_attempts where booking_id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'),
  'cs_fixture', 'pay_fixture', 13530), 'duplicate', 'Repeated paid event has no duplicate effect');

select is(public.paymongo_refresh_checkout(
  (select id from payments_private.checkout_attempts where booking_id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'),
  'cs_fixture', 'cancelled') ->> 'status', 'paid', 'A late cancel cannot overwrite a confirmed payment');

select is((select payment_status from public.bookings where id = '8fac1c77-19f3-41d3-ad97-8fd118d79730'),
  'paid', 'Shared booking reflects the confirmed payment');

select * from finish();
rollback;
