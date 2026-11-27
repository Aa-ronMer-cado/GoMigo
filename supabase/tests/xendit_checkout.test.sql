begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select no_plan();

insert into auth.users (id, email) values
  ('2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba01', 'xendit-traveler@example.test'),
  ('2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba02', 'xendit-outsider@example.test');
insert into public.amigo_profiles (id, display_name, description, area, age, gender, rate_centavos)
values ('2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba03', 'Test Amigo', 'Fixture', 'Manila', 30, 'unspecified', 10000);
insert into public.bookings (id, request_id, traveler_id, amigo_id, status, payment_status, starts_at, ends_at,
  meeting_label, meeting_lat, meeting_lng, subtotal_centavos, fee_centavos, total_centavos)
values ('2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba04', gen_random_uuid(),
  '2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba01', '2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba03',
  'accepted', 'unpaid', now() + interval '1 day', now() + interval '1 day 1 hour',
  'Test meetup', 14.58, 120.98, 10000, 1000, 11000);

select ok(not has_function_privilege('authenticated', 'public.xendit_record_payment(uuid,text,text,integer,text)', 'EXECUTE'),
  'Clients cannot settle payments');
select ok(not has_function_privilege('anon', 'public.xendit_bind_checkout(uuid,text,text,integer)', 'EXECUTE'),
  'Anonymous clients cannot bind checkouts');
set local role service_role;
select throws_ok($$select public.xendit_checkout_for_traveler('2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba04',
  '2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba02', true)$$, 'GM404', 'Booking unavailable', 'Only the traveler can open their checkout');
select throws_ok($$insert into payments_private.maya_checkout_attempts (booking_id, amount_centavos)
  values ('2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba04', 11000)$$,
  'GM409', 'New Maya checkouts are disabled', 'Previous clients cannot create new Maya attempts');
select set_config('gomigo_test.xendit_attempt', public.xendit_checkout_for_traveler(
  '2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba04', '2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba01', true)::text, true);
select is(current_setting('gomigo_test.xendit_attempt')::jsonb ->> 'can_create', 'true', 'Initial reservation creates one attempt');
select is(public.xendit_checkout_for_traveler('2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba04',
  '2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba01', true) ->> 'can_create', 'false', 'A retry cannot create another attempt');
select throws_ok($$select public.xendit_bind_checkout((current_setting('gomigo_test.xendit_attempt')::jsonb ->> 'id')::uuid,
  'ps-661f87c614802d6c402cd82d', 'https://dev.xen.to/test', 11001)$$,
  'GM409', 'Checkout mismatch', 'Binding rejects an amount mismatch');
select is(public.xendit_bind_checkout((current_setting('gomigo_test.xendit_attempt')::jsonb ->> 'id')::uuid,
  'ps-661f87c614802d6c402cd82d', 'https://dev.xen.to/test', 11000) ->> 'status', 'pending', 'Verified session binds');
select throws_ok($$select public.xendit_record_payment((current_setting('gomigo_test.xendit_attempt')::jsonb ->> 'id')::uuid,
  'ps-661f87c614802d6c402cd82d', 'paid', 11001, 'PHP')$$, 'GM409', 'Payment mismatch', 'Settlement rejects an amount mismatch');
select is(public.xendit_record_payment((current_setting('gomigo_test.xendit_attempt')::jsonb ->> 'id')::uuid,
  'ps-661f87c614802d6c402cd82d', 'paid', 11000, 'PHP') ->> 'status', 'paid', 'Verified payment settles');
select is(public.xendit_record_payment((current_setting('gomigo_test.xendit_attempt')::jsonb ->> 'id')::uuid,
  'ps-661f87c614802d6c402cd82d', 'cancelled', 11000, 'PHP') ->> 'status', 'paid', 'A late cancellation cannot downgrade payment');
reset role;
select is((select payment_status from public.bookings where id = '2c1c3ec2-32f8-4a3b-a99d-00a4ac3aba04'),
  'paid', 'Booking and checkout settle together');
select * from finish();
rollback;
