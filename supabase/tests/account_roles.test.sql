begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select no_plan();

insert into auth.users (id, raw_user_meta_data) values
  ('5ea00000-0000-4000-a000-000000000001', '{"gomigo_role":"reviewer"}'),
  ('5ea00000-0000-4000-a000-000000000002', '{"gomigo_role":"amigo"}'),
  ('5ea00000-0000-4000-a000-000000000003', '{}');
update public.profiles set role = 'reviewer' where id = '5ea00000-0000-4000-a000-000000000003';
insert into private.verification_reviewers (user_id) values
  ('5ea00000-0000-4000-a000-000000000001'),
  ('5ea00000-0000-4000-a000-000000000002'),
  ('5ea00000-0000-4000-a000-000000000003');
insert into private.demo_travelers values ('5ea00000-0000-4000-a000-000000000003');
insert into public.verification_submissions (id, traveler_id, applicant_name) values
  ('5ea00000-0000-4000-b000-000000000001', '5ea00000-0000-4000-a000-000000000001', 'Test Applicant'),
  ('5ea00000-0000-4000-b000-000000000003', '5ea00000-0000-4000-a000-000000000003', 'Earlier Applicant');

set local role authenticated;
set local request.jwt.claim.sub = '5ea00000-0000-4000-a000-000000000001';
select is((select role from public.profiles), 'traveler', 'Public signup cannot create a reviewer');
select is(public.is_verification_reviewer(), false, 'Traveler cannot use a legacy reviewer grant');
select is((select count(*) from public.verification_submissions), 1::bigint, 'Traveler only sees their own ID');

set local request.jwt.claim.sub = '5ea00000-0000-4000-a000-000000000002';
select is((select role from public.profiles), 'amigo', 'Amigo signup creates an Amigo account');
select is(public.is_verification_reviewer(), false, 'Amigo cannot use a legacy reviewer grant');
select is((select count(*) from public.verification_submissions), 0::bigint, 'Amigo cannot see another account’s ID');

set local request.jwt.claim.sub = '5ea00000-0000-4000-a000-000000000003';
select is((select role from public.profiles), 'reviewer', 'Reviewer account has its own role');
select is(public.is_verification_reviewer(), true, 'A dedicated reviewer with a grant can use ID Review');
select is(public.is_booking_demo_enabled(), false, 'Reviewer cannot act as a demo Traveler');
select is(public.my_amigo_id(), null::uuid, 'Reviewer has no Amigo identity');
select is((select count(*) from public.amigo_profiles), 0::bigint, 'Reviewer cannot browse Amigo profiles');
select is((select id from public.verification_submissions), '5ea00000-0000-4000-b000-000000000001'::uuid,
  'Reviewer can see other submissions and cannot access their own previous ID in the review queue');
select throws_ok(
  $$select public.submit_verification('5ea00000-0000-4000-b000-000000000003')$$,
  '42501', 'Sign in to submit your ID.', 'Reviewer cannot reuse the applicant submission workflow'
);
select throws_ok(
  $$select public.review_verification('5ea00000-0000-4000-b000-000000000003', 'approved')$$,
  '42501', 'That submission is unavailable.', 'Reviewer cannot approve their previous submission'
);
select is(public.review_verification('5ea00000-0000-4000-b000-000000000001', 'approved') ->> 'status',
  'approved', 'Reviewer can approve another user’s submission');

select * from finish();
rollback;
