alter table public.profiles
  drop constraint profiles_role_check,
  add constraint profiles_role_check check (role in ('traveler', 'amigo', 'reviewer'));

create or replace function private.is_verification_reviewer()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select from private.verification_reviewers r
    join public.profiles p on p.id = r.user_id
    where r.user_id = (select auth.uid()) and p.role = 'reviewer'
  );
$$;

create or replace function private.my_amigo_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select a.amigo_id from private.amigo_accounts a
  join public.profiles p on p.id = a.user_id
  where a.user_id = (select auth.uid()) and p.role = 'amigo';
$$;

create or replace function private.is_booking_demo_enabled()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select from private.demo_travelers d
    join public.profiles p on p.id = d.user_id
    where d.user_id = (select auth.uid()) and p.role = 'traveler'
  );
$$;

alter policy verification_owner_or_reviewer on public.verification_submissions using (
  (traveler_id = (select auth.uid()) and exists (
    select from public.profiles p where p.id = (select auth.uid()) and p.role = applicant_role
  )) or
  (traveler_id <> (select auth.uid()) and (select private.is_verification_reviewer()))
);

alter policy discoverable_amigos on public.amigo_profiles using (
  exists (select from public.profiles where id = (select auth.uid()) and role in ('traveler', 'amigo')) and
  ((verified and (not is_test or (select private.is_booking_demo_enabled()))) or id = (select private.my_amigo_id()))
);

create or replace function private.submit_verification(p_submission_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  applicant public.profiles%rowtype;
  submission public.verification_submissions%rowtype;
  object_prefix text;
begin
  select * into applicant from public.profiles
  where id = auth.uid() and role in ('traveler', 'amigo') for update;
  if not found or p_submission_id is null then
    raise exception 'Sign in to submit your ID.' using errcode = '42501';
  end if;
  select * into submission from public.verification_submissions
  where id = p_submission_id and traveler_id = applicant.id;
  if found then
    return to_jsonb(submission);
  end if;
  if exists (
    select from public.verification_submissions
    where traveler_id = applicant.id and status in ('pending', 'approved')
  ) then
    raise exception 'You already have an active ID submission.';
  end if;
  object_prefix := applicant.id::text || '/' || p_submission_id::text || '/';
  if (
    select count(*) from storage.objects
    where bucket_id = 'verification-ids' and name in (object_prefix || 'front', object_prefix || 'back')
  ) <> 2 then
    raise exception 'Upload both sides of your ID before submitting.';
  end if;
  insert into public.verification_submissions (id, traveler_id, applicant_name, applicant_role)
  values (p_submission_id, applicant.id, applicant.display_name, applicant.role)
  returning * into submission;
  return to_jsonb(submission);
end;
$$;
