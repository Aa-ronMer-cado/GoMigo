alter table public.verification_submissions
  add column reviewed_display_name text check (char_length(btrim(reviewed_display_name)) between 1 and 80),
  add column reviewed_gender text check (reviewed_gender in ('woman', 'man', 'nonbinary', 'unspecified')),
  add constraint amigo_review_identity_pair check (
    (reviewed_display_name is null) = (reviewed_gender is null)
  );

alter table public.amigo_profiles
  alter column age drop not null,
  add column onboarding_completed_at timestamptz;

create function private.require_amigo_review_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.applicant_role = 'amigo' and old.status = 'pending' and new.status = 'approved'
     and new.reviewed_display_name is null then
    raise exception 'Enter the Amigo’s verified name and gender before approving.';
  end if;
  return new;
end;
$$;
revoke execute on function private.require_amigo_review_identity() from public, anon, authenticated;

create trigger require_amigo_review_identity before update of status on public.verification_submissions
for each row execute function private.require_amigo_review_identity();

create function private.review_amigo_identity(p_submission_id uuid, p_display_name text, p_gender text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  reviewer uuid := auth.uid();
  submission public.verification_submissions%rowtype;
  verified_name text := nullif(btrim(p_display_name), '');
begin
  if not private.is_verification_reviewer() then
    raise exception 'Reviewer access is required.' using errcode = '42501';
  end if;
  if verified_name is null or char_length(verified_name) > 80 or p_gender is null or
     p_gender not in ('woman', 'man', 'nonbinary', 'unspecified') then
    raise exception 'Enter the Amigo’s verified name and select a gender.';
  end if;
  select * into submission from public.verification_submissions where id = p_submission_id
    and applicant_role = 'amigo' and traveler_id <> reviewer for update;
  if not found then
    raise exception 'That submission is unavailable.' using errcode = '42501';
  end if;
  if submission.reviewed_display_name is not null then
    if submission.status = 'approved' and submission.reviewed_display_name = verified_name
       and submission.reviewed_gender = p_gender then
      return to_jsonb(submission);
    end if;
    raise exception 'This submission was already reviewed.';
  end if;
  if submission.status = 'rejected' then
    raise exception 'This submission was already reviewed.';
  end if;
  update public.verification_submissions
  set reviewed_display_name = verified_name, reviewed_gender = p_gender,
      reviewed_by = case when status = 'approved' then reviewer else reviewed_by end,
      reviewed_at = case when status = 'approved' then clock_timestamp() else reviewed_at end
  where id = p_submission_id returning * into submission;
  if submission.status = 'pending' then
    submission := jsonb_populate_record(null::public.verification_submissions,
      private.review_verification(p_submission_id, 'approved', null));
  end if;
  update public.amigo_profiles a set available = false
    from private.amigo_accounts aa
    where aa.user_id = submission.traveler_id and aa.amigo_id = a.id
      and a.onboarding_completed_at is null;
  return to_jsonb(submission);
end;
$$;

create function public.review_amigo_identity(p_submission_id uuid, p_display_name text, p_gender text)
returns jsonb language sql set search_path = '' as $$
  select private.review_amigo_identity(p_submission_id, p_display_name, p_gender);
$$;
revoke execute on function private.review_amigo_identity(uuid, text, text),
  public.review_amigo_identity(uuid, text, text) from public, anon, authenticated, service_role;
grant execute on function private.review_amigo_identity(uuid, text, text),
  public.review_amigo_identity(uuid, text, text) to authenticated;

create or replace function private.save_amigo_profile(
  p_display_name text, p_description text, p_area text, p_languages text[], p_interests text[],
  p_age integer, p_gender text, p_rate_centavos integer, p_photo_path text,
  p_discovery_latitude double precision, p_discovery_longitude double precision
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  amigo public.amigo_profiles%rowtype;
  own_id uuid;
  verified_name text;
  verified_gender text;
  modern boolean;
  allowed_interests constant text[] := array['Food & Dining', 'Nature & Adventure', 'Shopping', 'Photography', 'Nightlife', 'Local Culture', 'Arts & Museums', 'Outdoor Activities', 'Local Experiences'];
begin
  perform from public.profiles where id = actor and role = 'amigo' for update;
  if not found then
    raise exception 'Sign in as an Amigo to edit your profile.' using errcode = '42501';
  end if;
  own_id := private.my_amigo_id();
  select reviewed_display_name, reviewed_gender into verified_name, verified_gender
    from public.verification_submissions where traveler_id = actor and status = 'approved';
  modern := p_display_name is null or verified_name is not null;
  if modern then
    select * into amigo from public.amigo_profiles where id = own_id;
    if verified_name is null and (amigo.id is null or not amigo.verified) then
      raise exception 'Wait for your reviewer to confirm your name and gender.' using errcode = '42501';
    end if;
    p_display_name := coalesce(verified_name, amigo.display_name);
    p_gender := coalesce(verified_gender, amigo.gender);
    p_age := amigo.age;
    p_languages := coalesce(amigo.languages, '{}');
    if p_description is null or regexp_count(p_description, '[^[:space:]]+') < 30 then
      raise exception 'Write at least 30 words about yourself.';
    end if;
    if p_rate_centavos is null or p_rate_centavos not between 20000 and 150000 then
      raise exception 'Enter an hourly rate from PHP 200 to PHP 1,500.';
    end if;
    if p_discovery_latitude is null or p_discovery_longitude is null then
      raise exception 'Set your service area from your current location.';
    end if;
    if p_interests is null or not (p_interests <@ (allowed_interests || coalesce(amigo.interests, '{}'))) then
      raise exception 'Choose interests from the supplied options.';
    end if;
    if p_discovery_latitude between -90 and 90 and p_discovery_longitude between -180 and 180 then
      p_discovery_latitude := round(p_discovery_latitude::numeric, 2);
      p_discovery_longitude := round(p_discovery_longitude::numeric, 2);
    end if;
  end if;
  if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 80 or
    p_description is null or char_length(btrim(p_description)) not between 1 and 1500 or
    p_area is null or char_length(btrim(p_area)) not between 1 and 160 or
    (not modern and p_age is null) or p_age not between 18 and 120 or
    p_gender is null or p_gender not in ('woman', 'man', 'nonbinary', 'unspecified') or
    p_rate_centavos is null or p_rate_centavos not between 10000 and 10000000 then
    raise exception 'Check your name, description, area, age, gender and hourly rate.';
  end if;
  if cardinality(p_languages) is null or cardinality(p_languages) > 20 or (not modern and cardinality(p_languages) = 0) or
    cardinality(p_interests) is null or cardinality(p_interests) > 20 or
    exists (select from unnest(p_languages || p_interests) as entry
      where entry is null or char_length(btrim(entry)) not between 1 and 80) then
    raise exception 'Enter a language and use up to 20 languages and 20 interests.';
  end if;
  if (p_discovery_latitude is null) <> (p_discovery_longitude is null) or
    p_discovery_latitude not between -90 and 90 or p_discovery_longitude not between -180 and 180 then
    raise exception 'Choose valid public service area coordinates.';
  end if;
  if p_photo_path is not null and (
    split_part(p_photo_path, '/', 1) <> actor::text or
    not exists (select from storage.objects where bucket_id = 'amigo-photos' and name = p_photo_path)
  ) then
    raise exception 'Choose a photo uploaded by this Amigo.' using errcode = '42501';
  end if;

  if own_id is null then
    insert into public.amigo_profiles (
      display_name, description, area, languages, interests, age, gender, rate_centavos, photo_path,
      discovery_latitude, discovery_longitude, verified, available, onboarding_completed_at
    ) values (
      btrim(p_display_name), btrim(p_description), btrim(p_area), p_languages, p_interests, p_age,
      p_gender, p_rate_centavos, p_photo_path, p_discovery_latitude, p_discovery_longitude,
      exists (select from public.verification_submissions where traveler_id = actor and status = 'approved'),
      false, case when modern then clock_timestamp() end
    ) returning * into amigo;
    insert into private.amigo_accounts (amigo_id, user_id) values (amigo.id, actor);
  else
    update public.amigo_profiles set display_name = btrim(p_display_name),
      description = btrim(p_description), area = btrim(p_area), languages = p_languages,
      interests = p_interests, age = p_age, gender = p_gender, rate_centavos = p_rate_centavos,
      photo_path = p_photo_path, discovery_latitude = p_discovery_latitude,
      discovery_longitude = p_discovery_longitude,
      onboarding_completed_at = case when modern then coalesce(onboarding_completed_at, clock_timestamp()) else onboarding_completed_at end
    where id = own_id returning * into amigo;
  end if;
  update public.profiles set display_name = amigo.display_name where id = actor;
  return to_jsonb(amigo);
end;
$$;

create or replace function private.set_amigo_availability(p_available boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_available is null then
    raise exception 'Choose whether you are available.';
  end if;
  update public.amigo_profiles set available = p_available
  where id = (select private.my_amigo_id()) and (not p_available or (verified and (onboarding_completed_at is not null or not exists (
    select from public.verification_submissions where traveler_id = auth.uid() and status = 'approved'
      and reviewed_display_name is not null
  ))));
  if not found then
    raise exception 'Complete your profile and ID verification before becoming available.' using errcode = '42501';
  end if;
  return p_available;
end;
$$;

