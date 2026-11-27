begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select no_plan();

insert into auth.users (id, raw_user_meta_data) values
  ('4aa00000-0000-4000-a000-000000000001', '{"display_name":"Test Amigo","gomigo_role":"amigo"}'),
  ('4aa00000-0000-4000-a000-000000000002', '{"display_name":"Other Amigo","gomigo_role":"amigo"}'),
  ('4aa00000-0000-4000-a000-000000000003', '{"display_name":"Test Traveler"}'),
  ('4aa00000-0000-4000-a000-000000000004', '{"display_name":"Other Traveler"}'),
  ('4aa00000-0000-4000-a000-000000000005', '{"display_name":"Test Reviewer"}');
update public.profiles set role = 'reviewer' where id = '4aa00000-0000-4000-a000-000000000005';
insert into private.verification_reviewers (user_id) values ('4aa00000-0000-4000-a000-000000000005');
insert into public.verification_submissions (id, traveler_id, applicant_name, status, reviewed_by, reviewed_at)
values
  ('4aa00000-0000-4000-b000-000000000003','4aa00000-0000-4000-a000-000000000003',
    'Test Traveler','approved','4aa00000-0000-4000-a000-000000000005',now()),
  ('4aa00000-0000-4000-b000-000000000004','4aa00000-0000-4000-a000-000000000004',
    'Other Traveler','approved','4aa00000-0000-4000-a000-000000000005',now());
select is((select public from storage.buckets where id = 'verification-ids'), false,
  'ID uploads remain in a private bucket');

set local role authenticated;
set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000001';
select is((select role from public.profiles), 'amigo', 'New Amigo has a persisted ordinary role');
select is(public.my_amigo_id(), null::uuid, 'Signup leaves discovery profile empty');
select is(public.is_verification_reviewer(), false, 'Amigo signup does not confer admin access');
select throws_ok(
  $$update public.profiles set role = 'traveler'$$, '42501', null, 'Amigo cannot change roles'
);
reset role;
update auth.users
set raw_user_meta_data = '{"display_name":"Test Amigo","gomigo_role":"traveler"}'
where id = '4aa00000-0000-4000-a000-000000000001';
set local role authenticated;
select is((select role from public.profiles), 'amigo', 'Later metadata edits cannot change the saved role');
select throws_ok(
  $$select public.submit_verification('4aa00000-0000-4000-b000-000000000001')$$,
  'P0001', 'Upload both sides of your ID before submitting.', 'Amigo must upload both sides'
);
insert into storage.objects (bucket_id, name) values
  ('verification-ids', '4aa00000-0000-4000-a000-000000000001/4aa00000-0000-4000-b000-000000000001/front'),
  ('verification-ids', '4aa00000-0000-4000-a000-000000000001/4aa00000-0000-4000-b000-000000000001/back'),
  ('verification-ids', '4aa00000-0000-4000-a000-000000000001/4aa00000-0000-4000-b000-000000000006/front'),
  ('verification-ids', '4aa00000-0000-4000-a000-000000000001/4aa00000-0000-4000-b000-000000000006/back'),
  ('amigo-photos', '4aa00000-0000-4000-a000-000000000001/4aa00000-0000-4000-b000-000000000001.jpg');
select is(
  public.submit_verification('4aa00000-0000-4000-b000-000000000001') ->> 'applicant_role',
  'amigo', 'Amigo verification enters the shared review queue with the expected role'
);
select lives_ok(
  $$select public.save_amigo_profile('Test Amigo', 'Test description', 'Cebu',
    array['Cebuano'], array['Markets'], 25, 'unspecified', 30000,
    '4aa00000-0000-4000-a000-000000000001/4aa00000-0000-4000-b000-000000000001.jpg', 10.3167, 123.8907)$$,
  'Amigo can create a discovery profile with their own profile photo'
);
do $$
begin
  perform set_config('gomigo_test.amigo_id', public.my_amigo_id()::text, true);
end;
$$;
select is((select available from public.amigo_profiles where id = public.my_amigo_id()), false,
  'New Amigo starts unavailable');
select throws_ok(
  $$select public.set_amigo_availability(true)$$, '42501', null, 'Pending Amigo cannot become available'
);
select throws_ok(
  $$select public.review_verification('4aa00000-0000-4000-b000-000000000001', 'approved')$$,
  '42501', 'Reviewer access is required.', 'Amigo cannot decide ID submissions'
);
select is((select count(*) from storage.objects where bucket_id = 'verification-ids'), 0::bigint,
  'Applicant cannot download private ID images with an ordinary session');

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000002';
select is((select count(*) from public.verification_submissions), 0::bigint, 'Another Amigo cannot see the application');
select is((select count(*) from storage.objects where bucket_id = 'verification-ids'), 0::bigint,
  'Other Amigo cannot download ID images');
select throws_ok(
  $$select public.save_amigo_profile('Other Amigo', 'Test description', 'Cebu',
    array['Cebuano'], array[]::text[], 25, 'unspecified', 30000,
    '4aa00000-0000-4000-a000-000000000001/4aa00000-0000-4000-b000-000000000001.jpg')$$,
  '42501', 'Choose a photo uploaded by this Amigo.', 'Amigo cannot attach another account’s photo'
);

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000005';
select is((select count(*) from storage.objects where bucket_id = 'verification-ids'), 2::bigint,
  'Reviewer can open the submitted pair only');
select is(
  public.review_verification('4aa00000-0000-4000-b000-000000000001', 'rejected', 'Please resubmit a clear image.')
    ->> 'status',
  'rejected', 'Reviewer can reject an Amigo application'
);

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000001';
select is((select rejection_reason from public.verification_submissions
    where id = '4aa00000-0000-4000-b000-000000000001'),
  'Please resubmit a clear image.', 'Amigo sees the saved rejection reason');
select is(public.submit_verification('4aa00000-0000-4000-b000-000000000006') ->> 'status', 'pending',
  'Amigo can resubmit with a new image pair after rejection');

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000005';
select throws_ok(
  $$select public.review_verification('4aa00000-0000-4000-b000-000000000006', 'approved')$$,
  'P0001', 'Enter the Amigo’s verified name and gender before approving.', 'Amigo approval requires reviewer identity'
);
select is(
  public.review_amigo_identity('4aa00000-0000-4000-b000-000000000006', 'Test Amigo', 'woman') ->> 'status',
  'approved', 'Reviewer approves a resubmission in the existing workflow'
);

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000001';
select is((select verified from public.amigo_profiles where id = public.my_amigo_id()), true,
  'Approval also updates the existing discovery profile');
select throws_ok(
  $$select public.review_amigo_identity('4aa00000-0000-4000-b000-000000000006', 'Changed name', 'man')$$,
  '42501', 'Reviewer access is required.', 'An applicant cannot change verified details'
);
select throws_ok($$select public.set_amigo_availability(true)$$, '42501', null,
  'Approved Amigo cannot go available before completing setup');
select throws_ok(
  $$select public.save_amigo_profile(null, 'Too short.', 'Cebu', null, '{}', null, null, 30000, null, 10.3167, 123.8907)$$,
  'P0001', 'Write at least 30 words about yourself.', 'Profile validates the bio on the server'
);
select is(public.save_amigo_profile('Unverified name',
  'I enjoy helping visitors explore the city markets and local food with time to take photos near the waterfront and discover favorite places together at a comfortable pace for everyone.',
  'Cebu', null, array['Local Culture', 'Photography'], null, 'man', 30000, null, 10.3167, 123.8907
) ->> 'gender', 'woman', 'Profile saves reviewer identity instead of client supplied fields');
select is((select interests from public.amigo_profiles where id = public.my_amigo_id()),
  array['Local Culture', 'Photography'], 'Multiple interests are saved');
select is(public.set_amigo_availability(true), true, 'Verified Amigo can opt in to availability');
select throws_ok(
  $$select public.quote_booking(public.my_amigo_id(), now() + interval '5 minutes', now() + interval '35 minutes')$$,
  '42501', null, 'Amigo role cannot request a Traveler quote'
);

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000003';
select is((select display_name from public.amigo_profiles
    where id = current_setting('gomigo_test.amigo_id')::uuid),
  'Test Amigo', 'Traveler discovers the verified profile saved by its Amigo');
select throws_ok(
  $$select public.save_amigo_profile('Traveler', 'Test description', 'Cebu',
    array['Cebuano'], array[]::text[], 25, 'unspecified', 30000)$$,
  '42501', null, 'Traveler cannot create an Amigo discovery profile'
);
do $$
begin
  perform set_config('gomigo_test.booking_one', public.create_booking(
    current_setting('gomigo_test.amigo_id')::uuid, now() + interval '5 minutes', now() + interval '65 minutes',
    'Cebu meeting point', 10.3167, 123.8907, 'Traveler’s market plans',
    '4aa00000-0000-4000-c000-000000000001'
  ) ->> 'id', true);
end;
$$;

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000004';
do $$
begin
  perform set_config('gomigo_test.booking_two', public.create_booking(
    current_setting('gomigo_test.amigo_id')::uuid, now() + interval '10 minutes', now() + interval '70 minutes',
    'Another meeting point', 10.3167, 123.8907, '',
    '4aa00000-0000-4000-c000-000000000002'
  ) ->> 'id', true);
end;
$$;

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000002';
select throws_ok(
  $$select public.respond_to_booking(current_setting('gomigo_test.booking_one')::uuid, 'accepted')$$,
  '42501', null, 'Another Amigo cannot accept the booking'
);
select is((select count(*) from public.get_amigo_booking_travelers(array[current_setting('gomigo_test.booking_one')::uuid])),
  0::bigint, 'Another Amigo cannot retrieve Traveler details');

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000001';
select is((select display_name from public.get_amigo_booking_travelers(array[current_setting('gomigo_test.booking_one')::uuid])),
  'Test Traveler', 'Assigned Amigo can see the requesting Traveler');
select is(public.set_amigo_availability(false), false, 'Amigo can turn availability off');
select throws_ok(
  $$select public.respond_to_booking(current_setting('gomigo_test.booking_one')::uuid, 'accepted')$$,
  'P0001', 'This Amigo is unavailable.', 'Backend rejects acceptance while offline'
);
set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000003';
select throws_ok(
  $$select public.quote_booking(current_setting('gomigo_test.amigo_id')::uuid,
    now() + interval '5 minutes', now() + interval '35 minutes')$$,
  'P0001', 'This Amigo is unavailable.', 'Turning availability off blocks new quotes'
);
set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000001';
select is(public.set_amigo_availability(true), true, 'The switch can be re-enabled');
select is(public.respond_to_booking(current_setting('gomigo_test.booking_one')::uuid, 'accepted') ->> 'status',
  'accepted', 'Amigo accepts the shared request');
select is(public.respond_to_booking(current_setting('gomigo_test.booking_one')::uuid, 'accepted') ->> 'status',
  'accepted', 'Accept retries are idempotent');
select throws_ok(
  $$select public.respond_to_booking(current_setting('gomigo_test.booking_two')::uuid, 'accepted')$$,
  '23P01', 'One of the participants already has an accepted booking at that time.',
  'Two different Travelers cannot book the same Amigo in overlapping time slots'
);
select is(public.respond_to_booking(current_setting('gomigo_test.booking_two')::uuid, 'declined', 'Schedule conflict')
  ->> 'decline_reason', 'Schedule conflict', 'Decline saves the reason on the shared row');
select is((select array_length(array_agg(display_name), 1) from public.get_amigo_booking_travelers(
  array[current_setting('gomigo_test.booking_one')::uuid, current_setting('gomigo_test.booking_two')::uuid])),
  2, 'Authorized details also support booking history');
select lives_ok(
  $$insert into public.booking_messages (booking_id, sender_id, body)
    values (current_setting('gomigo_test.booking_one')::uuid, public.my_amigo_id(), 'Test Amigo message')$$,
  'Assigned Amigo writes shared chat'
);
select throws_ok(
  $$select public.start_booking_session(current_setting('gomigo_test.booking_one')::uuid)$$,
  'P0001', 'A paid booking can start 15 minutes before its scheduled time.', 'Amigo cannot start an unpaid session'
);

reset role;
set local role service_role;
update public.bookings set payment_status = 'paid' where id = current_setting('gomigo_test.booking_one')::uuid;
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000001';
select lives_ok($$select public.start_booking_session(current_setting('gomigo_test.booking_one')::uuid)$$,
  'Amigo starts the paid session');
select lives_ok($$select public.set_booking_location(current_setting('gomigo_test.booking_one')::uuid, 10.3167, 123.8907)$$,
  'Amigo can explicitly share a position');
select lives_ok($$select public.set_route_recording(current_setting('gomigo_test.booking_one')::uuid, true)$$,
  'Amigo can opt into route recording during the session');
select lives_ok($$select public.append_route_point(current_setting('gomigo_test.booking_one')::uuid, 10.3167, 123.8907)$$,
  'Amigo contributes a route point');

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000004';
select is((select count(*) from public.booking_messages), 0::bigint, 'Nonparticipant cannot see messages');
select throws_ok(
  $$insert into public.booking_messages (booking_id, body)
    values (current_setting('gomigo_test.booking_one')::uuid, 'Nonparticipant message')$$,
  '42501', null, 'Nonparticipant cannot send a booking message'
);
select is((select count(*) from public.booking_locations), 0::bigint, 'Nonparticipant cannot see the position');
select is((select count(*) from public.booking_route_points), 0::bigint, 'Nonparticipant cannot access the route');
select is((select count(*) from public.booking_sessions), 0::bigint, 'Nonparticipant cannot access the session');

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000003';
select is((select status from public.bookings where id = current_setting('gomigo_test.booking_one')::uuid),
  'accepted', 'Traveler sees the Amigo’s accepted status');
select is((select body from public.booking_messages where booking_id = current_setting('gomigo_test.booking_one')::uuid),
  'Test Amigo message', 'Traveler receives the same message');
select is((select latitude from public.booking_locations where booking_id = current_setting('gomigo_test.booking_one')::uuid),
  10.3167::double precision, 'Traveler can see the shared Amigo position');
select is((select count(*) from public.booking_sessions where booking_id = current_setting('gomigo_test.booking_one')::uuid
    and ended_at is null),
  1::bigint, 'Traveler sees the same running session');
select lives_ok($$select public.complete_booking_session(current_setting('gomigo_test.booking_one')::uuid)$$,
  'Traveler completes the same session the Amigo started');
select lives_ok(
  $$insert into public.reviews (booking_id, amigo_id, rating)
    values (current_setting('gomigo_test.booking_one')::uuid, current_setting('gomigo_test.amigo_id')::uuid, 5)$$,
  'Traveler can still submit an Amigo rating'
);

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000001';
select is((select status from public.bookings where id = current_setting('gomigo_test.booking_one')::uuid),
  'completed', 'Amigo sees the Traveler’s completion');
select is((select count(*) from public.booking_locations), 0::bigint, 'Live location is no longer visible after completion');
select is((select count(*) from public.booking_route_points), 1::bigint, 'Participants can see the completed route');
select is(public.review_traveler(current_setting('gomigo_test.booking_one')::uuid, 4, 'Demo review') ->> 'author_role',
  'amigo', 'Amigo can rate the Traveler on the same shared booking');
select throws_ok($$select public.review_traveler(current_setting('gomigo_test.booking_one')::uuid, 5)$$,
  'P0001', 'You already reviewed this booking.', 'Amigo may submit only one rating per booking');
select is(public.get_demo_amigo_earnings() ->> 'available_centavos', '30000',
  'Completing a test-paid booking adds its server subtotal to simulated earnings');
select lives_ok($$select public.save_demo_amigo_payout_method('maya','Fictional payout')$$,
  'Amigo can configure a fictional payout label');
select is(public.simulate_amigo_withdrawal(10000, '4aa00000-0000-4000-d000-000000000001') ->> 'status',
  'simulated', 'Withdrawal result is explicitly simulated');
select is(public.simulate_amigo_withdrawal(10000, '4aa00000-0000-4000-d000-000000000001') ->> 'amount_centavos',
  '10000', 'Same withdrawal retry returns the original amount');
select is(public.get_demo_amigo_earnings() ->> 'available_centavos', '20000', 'Retry does not debit the balance twice');
select throws_ok($$select public.simulate_amigo_withdrawal(20001, '4aa00000-0000-4000-d000-000000000002')$$,
  'P0001', 'The simulated balance is too low for this withdrawal.', 'Backend prevents an overdrawn balance');

set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000003';
select is((select count(*) from public.reviews where booking_id = current_setting('gomigo_test.booking_one')::uuid),
  2::bigint, 'Both directional reviews are visible to the reviewed Traveler');
select throws_ok($$select public.get_demo_amigo_earnings()$$, '42501', null, 'Traveler cannot read Amigo earnings');
set local request.jwt.claim.sub = '4aa00000-0000-4000-a000-000000000004';
select is((select count(*) from public.reviews where booking_id = current_setting('gomigo_test.booking_one')::uuid
    and author_role = 'amigo'),
  0::bigint, 'A third party cannot read the private Traveler review');

reset role;
select * from finish();
rollback;
