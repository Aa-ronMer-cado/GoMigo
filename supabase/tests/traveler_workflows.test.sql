begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select no_plan();

insert into auth.users (id, raw_user_meta_data) values
  ('fd650000-2b7a-43f1-8cde-c0061da0e001', '{"display_name":"Fictional Traveler","role":"amigo"}'),
  ('fd650000-2b7a-43f1-8cde-c0061da0e002', '{"display_name":"Fictional Reviewer"}'),
  ('fd650000-2b7a-43f1-8cde-c0061da0e003', '{"display_name":"Fictional Outsider"}'),
  ('fd650000-2b7a-43f1-8cde-c0061da0e004', '{"display_name":"Fictional Amigo","gomigo_role":"amigo"}');
update public.profiles set role = 'reviewer' where id = 'fd650000-2b7a-43f1-8cde-c0061da0e002';
insert into private.verification_reviewers (user_id) values ('fd650000-2b7a-43f1-8cde-c0061da0e002');
insert into private.demo_travelers (user_id) values ('fd650000-2b7a-43f1-8cde-c0061da0e001');
insert into public.amigo_profiles (
  id, display_name, description, area, age, gender, rate_centavos, verified, is_test
) values
  ('fd650000-2b7a-43f1-8cde-c0061da0a001', 'Fictional Test Amigo', 'Test profile', 'Cebu', 25, 'woman', 30000, true, true),
  ('fd650000-2b7a-43f1-8cde-c0061da0a002', 'Fictional Amigo', 'Test profile', 'Cebu', 25, 'man', 30000, true, false);
insert into private.amigo_accounts (amigo_id, user_id)
values ('fd650000-2b7a-43f1-8cde-c0061da0a002', 'fd650000-2b7a-43f1-8cde-c0061da0e004');

set local role authenticated;
set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e001';

select is((select role from public.profiles limit 1), 'traveler', 'Signup metadata cannot assign a trusted role');
select is((select count(*) from public.profiles), 1::bigint, 'Profiles are private to their account');
select is(public.is_booking_demo_enabled(), true, 'Explicit demo allowance enables simulated workflow');
select is(public.is_verification_reviewer(), false, 'A traveler has no reviewer privilege');
select throws_ok(
  $$update public.profiles set role = 'amigo'$$, '42501', null, 'Clients cannot edit their role'
);
select throws_ok(
  $$select public.submit_verification('fd650000-2b7a-43f1-8cde-c0061da0f001')$$,
  'P0001', 'Upload both sides of your ID before submitting.', 'Incomplete ID uploads cannot be submitted'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('verification-ids','fd650000-2b7a-43f1-8cde-c0061da0e003/fd650000-2b7a-43f1-8cde-c0061da0f001/front')$$,
  '42501', null, 'A traveler cannot upload files under another account'
);
insert into storage.objects (bucket_id, name) values
  ('verification-ids','fd650000-2b7a-43f1-8cde-c0061da0e001/fd650000-2b7a-43f1-8cde-c0061da0f001/front'),
  ('verification-ids','fd650000-2b7a-43f1-8cde-c0061da0e001/fd650000-2b7a-43f1-8cde-c0061da0f001/back');
select is(
  public.submit_verification('fd650000-2b7a-43f1-8cde-c0061da0f001') ->> 'status',
  'pending', 'Both private file records allow a pending submission'
);
select is(
  public.submit_verification('fd650000-2b7a-43f1-8cde-c0061da0f001') ->> 'status',
  'pending', 'Retrying a submission returns the same record'
);
select throws_ok(
  $$select public.review_verification('fd650000-2b7a-43f1-8cde-c0061da0f001','approved')$$,
  '42501', 'Reviewer access is required.', 'Traveler cannot approve their own ID'
);
select throws_ok(
  $$select public.create_booking(
    'fd650000-2b7a-43f1-8cde-c0061da0a001', now() + interval '5 minutes', now() + interval '65 minutes',
    'Meeting point', 10.3, 123.9, '', 'fd650000-2b7a-43f1-8cde-c0061da0b001'
  )$$, '42501', 'An approved ID is required to book.', 'Pending verification cannot book'
);

set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e003';
select is(
  (select count(*) from public.verification_submissions where id = 'fd650000-2b7a-43f1-8cde-c0061da0f001'),
  0::bigint, 'Other accounts cannot see a submission'
);
select is(
  (select count(*) from storage.objects where bucket_id = 'verification-ids' and name like '%c0061da0f001/%'),
  0::bigint, 'Other accounts cannot read private files'
);
select is(
  (select count(*) from public.amigo_profiles where id = 'fd650000-2b7a-43f1-8cde-c0061da0a001'),
  0::bigint, 'Demo profiles require an explicit allowance'
);

set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e002';
select is(public.is_verification_reviewer(), true, 'Backend-granted reviewer can open the queue');
select is(
  (select count(*) from storage.objects where bucket_id = 'verification-ids' and name like '%c0061da0f001/%'),
  2::bigint, 'Reviewer can read both files of a submitted ID'
);
select throws_ok(
  $$select public.review_verification('fd650000-2b7a-43f1-8cde-c0061da0f001','rejected')$$,
  'P0001', 'Choose approval or provide a rejection reason.', 'A rejection needs a reason'
);
select is(
  public.review_verification('fd650000-2b7a-43f1-8cde-c0061da0f001','approved') ->> 'reviewed_by',
  'fd650000-2b7a-43f1-8cde-c0061da0e002', 'Approval records the authenticated reviewer'
);
select is(
  public.review_verification('fd650000-2b7a-43f1-8cde-c0061da0f001','approved') ->> 'status',
  'approved', 'Identical review retry returns the recorded decision'
);
select throws_ok(
  $$select public.review_verification('fd650000-2b7a-43f1-8cde-c0061da0f001','rejected','Different decision')$$,
  'P0001', 'This submission was already reviewed.', 'A later decision cannot overwrite approval'
);

set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e001';
select is(
  (select status from public.verification_submissions where id = 'fd650000-2b7a-43f1-8cde-c0061da0f001'),
  'approved', 'Applicant can read the approval'
);
select is(
  public.quote_booking('fd650000-2b7a-43f1-8cde-c0061da0a001',now() + interval '5 minutes',now() + interval '35 minutes'),
  '{"subtotal_centavos":15000,"fee_centavos":0,"total_centavos":15000}'::jsonb,
  'Trusted rate is prorated and returned in centavos'
);

do $$
begin
  perform set_config('gomigo_test.booking_id', public.create_booking(
    'fd650000-2b7a-43f1-8cde-c0061da0a001', now() + interval '5 minutes', now() + interval '65 minutes',
    'Meeting point', 10.3, 123.9, '', 'fd650000-2b7a-43f1-8cde-c0061da0b001'
  ) ->> 'id', true);
  perform set_config('gomigo_test.overlap_id', public.create_booking(
    'fd650000-2b7a-43f1-8cde-c0061da0a002', now() + interval '6 minutes', now() + interval '66 minutes',
    'Meeting point', 10.3, 123.9, '', 'fd650000-2b7a-43f1-8cde-c0061da0b002'
  ) ->> 'id', true);
end;
$$;

select is(
  public.create_booking(
    'fd650000-2b7a-43f1-8cde-c0061da0a001', now() + interval '5 minutes', now() + interval '65 minutes',
    'Meeting point', 10.3, 123.9, '', 'fd650000-2b7a-43f1-8cde-c0061da0b001'
  ) ->> 'id', current_setting('gomigo_test.booking_id'), 'Retrying booking creation returns the original row'
);
select throws_ok(
  $$select public.create_booking(
    'fd650000-2b7a-43f1-8cde-c0061da0a001', now() + interval '5 minutes', now() + interval '65 minutes',
    'Different meeting point', 10.3, 123.9, '', 'fd650000-2b7a-43f1-8cde-c0061da0b001'
  )$$, 'P0001', 'Use a new request ID for changed booking details.', 'A changed payload cannot reuse an earlier request ID'
);
select throws_ok(
  $$update public.bookings set payment_status = 'paid' where id = current_setting('gomigo_test.booking_id')::uuid$$,
  '42501', null, 'A client cannot claim payment'
);
select throws_ok(
  $$select public.respond_to_booking(current_setting('gomigo_test.booking_id')::uuid,'accepted')$$,
  '42501', 'This booking is unavailable.', 'Traveler cannot accept a request as a real Amigo'
);
select is(
  public.simulate_amigo_response(current_setting('gomigo_test.booking_id')::uuid, 'accepted') ->> 'status',
  'accepted', 'Allowlisted traveler can simulate acceptance on a fictional Amigo'
);
select throws_ok(
  $$select public.simulate_amigo_response(current_setting('gomigo_test.overlap_id')::uuid,'accepted')$$,
  '42501', 'This booking is unavailable.', 'Simulation cannot impersonate a regular Amigo'
);

set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e004';
select throws_ok(
  $$select public.respond_to_booking(current_setting('gomigo_test.overlap_id')::uuid,'accepted')$$,
  '23P01', 'One of the participants already has an accepted booking at that time.',
  'Database exclusion constraint forbids overlapping accepted bookings across Amigos'
);
select is(
  public.respond_to_booking(current_setting('gomigo_test.overlap_id')::uuid,'declined','Unavailable') ->> 'status',
  'declined', 'Actual assigned Amigo can decline their request'
);

set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e001';
select throws_ok(
  $$select public.start_booking_session(current_setting('gomigo_test.booking_id')::uuid)$$,
  'P0001', 'A paid booking can start 15 minutes before its scheduled time.', 'An unpaid session cannot start'
);
select is(
  public.simulate_amigo_message(current_setting('gomigo_test.booking_id')::uuid,'Fictional test message') ->> 'is_test',
  'true', 'Simulated chat is explicitly marked'
);
insert into public.booking_messages (id, booking_id, body) values
  ('fd650000-2b7a-43f1-8cde-c0061da0c001', current_setting('gomigo_test.booking_id')::uuid, 'Test reply')
on conflict (id) do nothing;
insert into public.booking_messages (id, booking_id, body) values
  ('fd650000-2b7a-43f1-8cde-c0061da0c001', current_setting('gomigo_test.booking_id')::uuid, 'Test reply')
on conflict (id) do nothing;
select is(
  (select count(*) from public.booking_messages where booking_id = current_setting('gomigo_test.booking_id')::uuid),
  2::bigint, 'Retrying the same chat message ID makes no duplicate'
);
select lives_ok(
  $$select public.set_booking_location(current_setting('gomigo_test.booking_id')::uuid,10.3,123.9)$$,
  'Traveler may explicitly share a position during an accepted meetup'
);

set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e003';
select is(
  (select count(*) from public.booking_messages where booking_id = current_setting('gomigo_test.booking_id')::uuid),
  0::bigint, 'Outsider cannot read booking chat'
);
select is(
  (select count(*) from public.booking_locations where booking_id = current_setting('gomigo_test.booking_id')::uuid),
  0::bigint, 'Outsider cannot read participant coordinates'
);
select throws_ok(
  $$select public.set_booking_location(current_setting('gomigo_test.booking_id')::uuid,10.3,123.9)$$,
  '42501', 'That booking is unavailable.', 'Outsider cannot publish a position to a booking'
);

reset role;
update public.bookings set payment_status = 'paid' where id = current_setting('gomigo_test.booking_id')::uuid;
set local role authenticated;
set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e001';
select throws_ok(
  $$select public.cancel_booking(current_setting('gomigo_test.booking_id')::uuid)$$,
  'P0001', 'Contact GoMigo support about cancelling a paid booking.', 'Paid cancellation requires a refund policy'
);
select lives_ok(
  $$select public.start_booking_session(current_setting('gomigo_test.booking_id')::uuid)$$,
  'Paid accepted booking can start in the test window'
);
select lives_ok(
  $$select public.set_route_recording(current_setting('gomigo_test.booking_id')::uuid,true)$$,
  'Participant can enable recording during an active session'
);
select lives_ok(
  $$select public.append_route_point(current_setting('gomigo_test.booking_id')::uuid,10.3,123.9,
     'fd650000-2b7a-43f1-8cde-c0061da0c002')$$, 'Authorized recording saves a point'
);
select lives_ok(
  $$select public.append_route_point(current_setting('gomigo_test.booking_id')::uuid,10.3,123.9,
     'fd650000-2b7a-43f1-8cde-c0061da0c002')$$, 'Repeating a point request is idempotent'
);
select lives_ok(
  $$select public.complete_booking_session(current_setting('gomigo_test.booking_id')::uuid)$$,
  'Started session can be completed'
);
select is(
  (select count(*) from public.booking_locations where booking_id = current_setting('gomigo_test.booking_id')::uuid),
  0::bigint, 'Completing a session removes live positions from participants'
);
select is(
  (select count(*) from public.booking_route_points where booking_id = current_setting('gomigo_test.booking_id')::uuid),
  1::bigint, 'Completed trip retains its recorded route point'
);
select lives_ok(
  $$insert into public.reviews (booking_id, amigo_id, rating)
    values (current_setting('gomigo_test.booking_id')::uuid, 'fd650000-2b7a-43f1-8cde-c0061da0a001', 5)$$,
  'Traveler can leave a rating without review text after completing their trip'
);
select throws_ok(
  $$insert into public.reviews (booking_id, amigo_id, rating)
    values (current_setting('gomigo_test.booking_id')::uuid, 'fd650000-2b7a-43f1-8cde-c0061da0a001', 4)$$,
  '23505', null, 'Only one review can be created for a completed booking'
);

reset role;
select * from finish();
rollback;
