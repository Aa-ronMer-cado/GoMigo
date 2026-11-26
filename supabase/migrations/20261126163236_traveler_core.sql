create extension if not exists btree_gist with schema extensions;
create schema if not exists private;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  role text not null default 'traveler' check (role in ('traveler', 'amigo'))
);

create function private.gomigo_create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(left(btrim(new.raw_user_meta_data ->> 'display_name'), 80), ''), 'Traveler')
  );
  return new;
end;
$$;
revoke all on function private.gomigo_create_profile() from public, anon, authenticated, service_role;
create trigger gomigo_profile_on_signup after insert on auth.users
for each row execute function private.gomigo_create_profile();

insert into public.profiles (id, display_name)
select id, coalesce(nullif(left(btrim(raw_user_meta_data ->> 'display_name'), 80), ''), 'Traveler')
from auth.users;

create table public.amigo_profiles (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  photo_url text,
  description text not null,
  area text not null,
  languages text[] not null default '{}',
  interests text[] not null default '{}',
  age smallint not null check (age between 18 and 120),
  gender text not null check (gender in ('woman', 'man', 'nonbinary', 'unspecified')),
  rate_centavos integer not null check (rate_centavos between 10000 and 10000000),
  verified boolean not null default false,
  is_test boolean not null default false
);

create table private.amigo_accounts (
  amigo_id uuid primary key references public.amigo_profiles (id) on delete cascade,
  user_id uuid unique not null references public.profiles (id) on delete cascade
);
create table private.demo_travelers (
  user_id uuid primary key references public.profiles (id) on delete cascade
);
create table private.verification_reviewers (
  user_id uuid primary key references public.profiles (id) on delete cascade
);
alter table private.amigo_accounts enable row level security;
alter table private.demo_travelers enable row level security;
alter table private.verification_reviewers enable row level security;

create function private.my_amigo_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select amigo_id from private.amigo_accounts where user_id = (select auth.uid());
$$;
create function private.is_booking_demo_enabled()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select from private.demo_travelers where user_id = (select auth.uid()));
$$;
create function private.is_verification_reviewer()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select from private.verification_reviewers where user_id = (select auth.uid()));
$$;

create function public.is_booking_demo_enabled()
returns boolean language sql stable set search_path = '' as $$
  select private.is_booking_demo_enabled();
$$;
create function public.is_verification_reviewer()
returns boolean language sql stable set search_path = '' as $$
  select private.is_verification_reviewer();
$$;

create table public.verification_submissions (
  id uuid primary key,
  traveler_id uuid not null references public.profiles (id),
  applicant_name text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  rejection_reason text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles (id),
  check ((status = 'pending') = (reviewed_at is null)),
  check ((status = 'pending') = (reviewed_by is null)),
  check ((status = 'rejected') = (rejection_reason is not null))
);
create unique index verification_one_open_submission
  on public.verification_submissions (traveler_id) where status in ('pending', 'approved');
create index verification_history_idx on public.verification_submissions (traveler_id, created_at desc);
create index verification_queue_idx on public.verification_submissions (status, created_at desc);
create index verification_reviewer_idx on public.verification_submissions (reviewed_by);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verification-ids', 'verification-ids', false, 8388608, array['image/jpeg', 'image/png', 'image/webp']);

create policy gomigo_id_owner_upload on storage.objects
for insert to authenticated with check (
  bucket_id = 'verification-ids' and
  split_part(name, '/', 1) = (select auth.uid())::text and
  name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/(front|back)$' and
  exists (select from public.profiles where id = (select auth.uid()) and role = 'traveler')
);
create policy gomigo_id_reviewer_download on storage.objects
for select to authenticated using (
  bucket_id = 'verification-ids' and
  (select private.is_verification_reviewer()) and
  exists (
    select from public.verification_submissions v
    where v.id::text = split_part(name, '/', 2)
      and v.traveler_id::text = split_part(name, '/', 1)
  )
);

create function private.submit_verification(p_submission_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  applicant public.profiles%rowtype;
  submission public.verification_submissions%rowtype;
  object_prefix text;
begin
  select * into applicant from public.profiles
  where id = auth.uid() and role = 'traveler' for update;
  if not found or p_submission_id is null then
    raise exception 'Sign in as a traveler to submit your ID.' using errcode = '42501';
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
  insert into public.verification_submissions (id, traveler_id, applicant_name)
  values (p_submission_id, applicant.id, applicant.display_name)
  returning * into submission;
  return to_jsonb(submission);
end;
$$;

create function private.review_verification(p_submission_id uuid, p_decision text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  reviewer uuid := auth.uid();
  submission public.verification_submissions%rowtype;
  reason text := nullif(btrim(p_reason), '');
begin
  if reviewer is null or not private.is_verification_reviewer() then
    raise exception 'Reviewer access is required.' using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') or
    (p_decision = 'rejected' and (reason is null or char_length(reason) > 500)) or
    (p_decision = 'approved' and reason is not null) then
    raise exception 'Choose approval or provide a rejection reason.';
  end if;
  select * into submission from public.verification_submissions
  where id = p_submission_id for update;
  if not found or reviewer = submission.traveler_id then
    raise exception 'That submission is unavailable.' using errcode = '42501';
  end if;
  if submission.status <> 'pending' then
    if submission.status = p_decision and submission.reviewed_by = reviewer and
      submission.rejection_reason is not distinct from reason then
      return to_jsonb(submission);
    end if;
    raise exception 'This submission was already reviewed.';
  end if;
  update public.verification_submissions
  set status = p_decision, reviewed_at = clock_timestamp(), reviewed_by = reviewer, rejection_reason = reason
  where id = p_submission_id returning * into submission;
  return to_jsonb(submission);
end;
$$;

create function public.submit_verification(p_submission_id uuid)
returns jsonb language sql set search_path = '' as $$
  select private.submit_verification(p_submission_id);
$$;

create function public.review_verification(p_submission_id uuid, p_decision text, p_reason text default null)
returns jsonb language sql set search_path = '' as $$
  select private.review_verification(p_submission_id, p_decision, p_reason);
$$;

create table public.favorites (
  traveler_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  amigo_id uuid not null references public.amigo_profiles (id) on delete cascade,
  primary key (traveler_id, amigo_id)
);
create index favorites_amigo_idx on public.favorites (amigo_id);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  traveler_id uuid not null references public.profiles (id),
  amigo_id uuid not null references public.amigo_profiles (id),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled', 'completed')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'pending', 'failed', 'cancelled', 'paid')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  meeting_label text not null check (char_length(btrim(meeting_label)) between 1 and 200),
  meeting_lat double precision not null check (meeting_lat between -90 and 90),
  meeting_lng double precision not null check (meeting_lng between -180 and 180),
  notes text not null default '' check (char_length(notes) <= 1000),
  subtotal_centavos integer not null check (subtotal_centavos > 0),
  fee_centavos integer not null check (fee_centavos >= 0),
  total_centavos integer not null check (total_centavos = subtotal_centavos + fee_centavos),
  decline_reason text,
  created_at timestamptz not null default now(),
  unique (traveler_id, request_id),
  check (isfinite(starts_at) and isfinite(ends_at) and ends_at > starts_at),
  exclude using gist (amigo_id with =, tstzrange(starts_at, ends_at, '[)') with &&) where (status = 'accepted'),
  exclude using gist (traveler_id with =, tstzrange(starts_at, ends_at, '[)') with &&) where (status = 'accepted')
);
create index bookings_traveler_history_idx on public.bookings (traveler_id, starts_at desc);
create index bookings_amigo_history_idx on public.bookings (amigo_id, starts_at desc);

create function private.quote_booking(p_amigo_id uuid, p_starts_at timestamptz, p_ends_at timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  hourly_rate integer;
  subtotal integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in to request a quote.' using errcode = '42501';
  end if;
  if p_starts_at is null or p_ends_at is null or not isfinite(p_starts_at) or not isfinite(p_ends_at) or
    p_starts_at <= now() or p_ends_at - p_starts_at not between interval '1 minute' and interval '8 hours' then
    raise exception 'Choose a future booking lasting from 1 minute to 8 hours.';
  end if;
  select rate_centavos into hourly_rate from public.amigo_profiles
  where id = p_amigo_id and verified and (not is_test or private.is_booking_demo_enabled());
  if not found then
    raise exception 'This Amigo is unavailable.';
  end if;
  -- Demo pricing prorates the hourly rate and rounds to the nearest centavo.
  subtotal := round(hourly_rate * extract(epoch from p_ends_at - p_starts_at) / 3600);
  return jsonb_build_object('subtotal_centavos', subtotal, 'fee_centavos', 0, 'total_centavos', subtotal);
end;
$$;

create function private.create_booking(
  p_amigo_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_meeting_label text, p_meeting_lat double precision, p_meeting_lng double precision,
  p_notes text, p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  booking public.bookings%rowtype;
  quote jsonb;
begin
  -- Serialize retries by traveler before checking the request ID and quote.
  perform from public.profiles where id = actor and role = 'traveler' for update;
  if not found or not exists (
    select from public.verification_submissions where traveler_id = actor and status = 'approved'
  ) then
    raise exception 'An approved ID is required to book.' using errcode = '42501';
  end if;
  select * into booking from public.bookings where traveler_id = actor and request_id = p_request_id;
  if found then
    if row(booking.amigo_id, booking.starts_at, booking.ends_at, booking.meeting_label,
          booking.meeting_lat, booking.meeting_lng, booking.notes)
      is distinct from row(p_amigo_id, p_starts_at, p_ends_at, btrim(p_meeting_label),
                          p_meeting_lat, p_meeting_lng, coalesce(btrim(p_notes), '')) then
      raise exception 'Use a new request ID for changed booking details.';
    end if;
    return to_jsonb(booking) - 'request_id';
  end if;
  quote := private.quote_booking(p_amigo_id, p_starts_at, p_ends_at);
  insert into public.bookings (
    request_id, traveler_id, amigo_id, starts_at, ends_at, meeting_label, meeting_lat, meeting_lng,
    notes, subtotal_centavos, fee_centavos, total_centavos
  ) values (
    p_request_id, actor, p_amigo_id, p_starts_at, p_ends_at, btrim(p_meeting_label), p_meeting_lat, p_meeting_lng,
    coalesce(btrim(p_notes), ''), (quote ->> 'subtotal_centavos')::integer,
    (quote ->> 'fee_centavos')::integer, (quote ->> 'total_centavos')::integer
  ) returning * into booking;
  return to_jsonb(booking) - 'request_id';
end;
$$;

create function private.respond_to_booking(p_booking_id uuid, p_decision text, p_reason text, simulate boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  booking public.bookings%rowtype;
  reason text := nullif(btrim(p_reason), '');
begin
  select * into booking from public.bookings b where b.id = p_booking_id and actor is not null and (
    (simulate is true and b.traveler_id = actor and (select private.is_booking_demo_enabled()) and
      exists (select from public.amigo_profiles a where a.id = b.amigo_id and a.is_test)) or
    (simulate is false and b.amigo_id = (select private.my_amigo_id()))
  ) for update;
  if not found then
    raise exception 'This booking is unavailable.' using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('accepted', 'declined') or
    (p_decision = 'accepted' and reason is not null) or char_length(reason) > 500 then
    raise exception 'Choose acceptance or decline and an optional decline reason.';
  end if;
  if booking.status = p_decision and booking.decline_reason is not distinct from reason then
    return to_jsonb(booking) - 'request_id';
  end if;
  if booking.status <> 'pending' or (p_decision = 'accepted' and booking.starts_at <= now()) then
    raise exception 'This booking can no longer be changed.';
  end if;
  update public.bookings set status = p_decision, decline_reason = reason
  where id = p_booking_id returning * into booking;
  return to_jsonb(booking) - 'request_id';
exception
  when exclusion_violation then
    raise exception 'One of the participants already has an accepted booking at that time.'
      using errcode = '23P01';
end;
$$;

create function private.cancel_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype;
begin
  select * into booking from public.bookings where id = p_booking_id and traveler_id = auth.uid() for update;
  if not found then
    raise exception 'This booking is unavailable.' using errcode = '42501';
  end if;
  if booking.status = 'cancelled' then
    return to_jsonb(booking) - 'request_id';
  end if;
  if booking.status not in ('pending', 'accepted') then
    raise exception 'This booking can no longer be cancelled.';
  end if;
  if booking.payment_status in ('pending', 'failed') then
    raise exception 'Cancel the open checkout before cancelling the booking.';
  end if;
  if booking.payment_status = 'paid' then
    raise exception 'Contact GoMigo support about cancelling a paid booking.';
  end if;
  update public.bookings set status = 'cancelled'
  where id = p_booking_id returning * into booking;
  return to_jsonb(booking) - 'request_id';
end;
$$;

create function public.quote_booking(p_amigo_id uuid, p_starts_at timestamptz, p_ends_at timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select private.quote_booking(p_amigo_id, p_starts_at, p_ends_at);
$$;
create function public.create_booking(
  p_amigo_id uuid, p_starts_at timestamptz, p_ends_at timestamptz,
  p_meeting_label text, p_meeting_lat double precision, p_meeting_lng double precision,
  p_notes text, p_request_id uuid
) returns jsonb language sql set search_path = '' as $$
  select private.create_booking(p_amigo_id, p_starts_at, p_ends_at, p_meeting_label,
    p_meeting_lat, p_meeting_lng, p_notes, p_request_id);
$$;
create function public.respond_to_booking(p_booking_id uuid, p_decision text, p_reason text default null)
returns jsonb language sql set search_path = '' as $$
  select private.respond_to_booking(p_booking_id, p_decision, p_reason, false);
$$;
create function public.simulate_amigo_response(p_booking_id uuid, p_decision text, p_reason text default null)
returns jsonb language sql set search_path = '' as $$
  select private.respond_to_booking(p_booking_id, p_decision, p_reason, true);
$$;
create function public.cancel_booking(p_booking_id uuid)
returns jsonb language sql set search_path = '' as $$
  select private.cancel_booking(p_booking_id);
$$;

create table public.booking_messages (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  sender_id uuid not null default auth.uid(),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  is_test boolean not null default false,
  created_at timestamptz not null default clock_timestamp()
);
create index booking_messages_history_idx on public.booking_messages (booking_id, created_at, id);

create table public.booking_locations (
  booking_id uuid not null references public.bookings (id) on delete cascade,
  participant_id uuid not null,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (booking_id, participant_id),
  check ((latitude is null) = (longitude is null))
);

create table public.booking_route_recordings (
  booking_id uuid not null references public.bookings (id) on delete cascade,
  participant_id uuid not null,
  enabled boolean not null,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (booking_id, participant_id)
);

create table public.booking_route_points (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  participant_id uuid not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  recorded_at timestamptz not null default clock_timestamp()
);
create index booking_route_points_history_idx on public.booking_route_points (booking_id, recorded_at, id);

create table public.booking_sessions (
  booking_id uuid primary key references public.bookings (id) on delete cascade,
  started_at timestamptz not null default clock_timestamp(),
  ended_at timestamptz,
  check (ended_at >= started_at)
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id),
  traveler_id uuid not null default auth.uid() references public.profiles (id),
  amigo_id uuid not null references public.amigo_profiles (id),
  rating smallint not null check (rating between 1 and 5),
  body text check (char_length(body) <= 1000),
  created_at timestamptz not null default clock_timestamp()
);
create index reviews_amigo_history_idx on public.reviews (amigo_id, created_at desc);
create index reviews_traveler_idx on public.reviews (traveler_id);

create function private.booking_for_participant(p_booking_id uuid)
returns public.bookings language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype;
begin
  select * into booking from public.bookings where id = p_booking_id and
    (traveler_id = (select auth.uid()) or amigo_id = (select private.my_amigo_id()))
  for update;
  if not found then
    raise exception 'That booking is unavailable.' using errcode = '42501';
  end if;
  return booking;
end;
$$;
revoke all on function private.booking_for_participant(uuid) from public, anon, authenticated, service_role;

create function private.simulate_amigo_message(p_booking_id uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype;
  message public.booking_messages%rowtype;
begin
  select * into booking from public.bookings
  where id = p_booking_id and traveler_id = auth.uid() and status = 'accepted' for update;
  if not found or not private.is_booking_demo_enabled() or not exists (
    select from public.amigo_profiles where id = booking.amigo_id and is_test
  ) then
    raise exception 'Simulated chat is unavailable.' using errcode = '42501';
  end if;
  insert into public.booking_messages (booking_id, sender_id, body, is_test)
  values (p_booking_id, booking.amigo_id, btrim(p_body), true)
  returning * into message;
  return to_jsonb(message);
end;
$$;

create function private.set_booking_location(p_booking_id uuid, p_latitude double precision, p_longitude double precision)
returns void language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype := private.booking_for_participant(p_booking_id);
  actor uuid := case when booking.traveler_id = auth.uid() then booking.traveler_id else booking.amigo_id end;
begin
  if (p_latitude is null) <> (p_longitude is null) then
    raise exception 'Supply both coordinates or stop sharing.';
  end if;
  if p_latitude is not null and (
    booking.status <> 'accepted' or now() not between booking.starts_at - interval '2 hours'
      and booking.ends_at + interval '1 hour'
  ) then
    raise exception 'Location sharing is available near the time of an accepted booking.';
  end if;
  insert into public.booking_locations (booking_id, participant_id, latitude, longitude)
  values (p_booking_id, actor, p_latitude, p_longitude)
  on conflict (booking_id, participant_id) do update
  set latitude = excluded.latitude, longitude = excluded.longitude, updated_at = excluded.updated_at;
end;
$$;

create function private.set_route_recording(p_booking_id uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype := private.booking_for_participant(p_booking_id);
  actor uuid := case when booking.traveler_id = auth.uid() then booking.traveler_id else booking.amigo_id end;
begin
  if p_enabled and (booking.status <> 'accepted' or not exists (
    select from public.booking_sessions where booking_id = p_booking_id and ended_at is null
  )) then
    raise exception 'Start the session before recording your route.';
  end if;
  insert into public.booking_route_recordings (booking_id, participant_id, enabled)
  values (p_booking_id, actor, p_enabled)
  on conflict (booking_id, participant_id) do update
  set enabled = excluded.enabled, updated_at = excluded.updated_at;
end;
$$;

create function private.append_route_point(p_booking_id uuid, p_latitude double precision,
  p_longitude double precision, p_point_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype := private.booking_for_participant(p_booking_id);
  actor uuid := case when booking.traveler_id = auth.uid() then booking.traveler_id else booking.amigo_id end;
  existing public.booking_route_points%rowtype;
begin
  select * into existing from public.booking_route_points where id = p_point_id;
  if found then
    if row(existing.booking_id, existing.participant_id, existing.latitude, existing.longitude)
      is distinct from row(p_booking_id, actor, p_latitude, p_longitude) then
      raise exception 'Use a new point ID for changed coordinates.';
    end if;
    return;
  end if;
  if booking.status <> 'accepted' or not exists (
    select from public.booking_route_recordings
    where booking_id = p_booking_id and participant_id = actor and enabled
  ) then
    raise exception 'Enable route recording before adding points.';
  end if;
  insert into public.booking_route_points (id, booking_id, participant_id, latitude, longitude)
  values (p_point_id, p_booking_id, actor, p_latitude, p_longitude);
end;
$$;

create function private.start_booking_session(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype := private.booking_for_participant(p_booking_id);
  trip public.booking_sessions%rowtype;
begin
  select * into trip from public.booking_sessions where booking_id = p_booking_id;
  if found then
    return to_jsonb(trip);
  end if;
  if booking.status <> 'accepted' or booking.payment_status <> 'paid' or
    now() < booking.starts_at - interval '15 minutes' or now() >= booking.ends_at then
    raise exception 'A paid booking can start 15 minutes before its scheduled time.';
  end if;
  insert into public.booking_sessions (booking_id) values (p_booking_id) returning * into trip;
  return to_jsonb(trip);
end;
$$;

create function private.complete_booking_session(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype := private.booking_for_participant(p_booking_id);
  trip public.booking_sessions%rowtype;
begin
  select * into trip from public.booking_sessions where booking_id = p_booking_id;
  if found and trip.ended_at is not null then
    return to_jsonb(trip);
  end if;
  if not found or booking.status <> 'accepted' then
    raise exception 'Start the session before completing it.';
  end if;
  update public.booking_sessions set ended_at = clock_timestamp()
  where booking_id = p_booking_id returning * into trip;
  update public.booking_locations set latitude = null, longitude = null, updated_at = clock_timestamp()
  where booking_id = p_booking_id;
  update public.booking_route_recordings set enabled = false, updated_at = clock_timestamp()
  where booking_id = p_booking_id;
  update public.bookings set status = 'completed' where id = p_booking_id;
  return to_jsonb(trip);
end;
$$;

create function public.simulate_amigo_message(p_booking_id uuid, p_body text)
returns jsonb language sql set search_path = '' as $$
  select private.simulate_amigo_message(p_booking_id, p_body);
$$;
create function public.set_booking_location(p_booking_id uuid, p_latitude double precision, p_longitude double precision)
returns void language sql set search_path = '' as $$
  select private.set_booking_location(p_booking_id, p_latitude, p_longitude);
$$;
create function public.set_route_recording(p_booking_id uuid, p_enabled boolean)
returns void language sql set search_path = '' as $$
  select private.set_route_recording(p_booking_id, p_enabled);
$$;
create function public.append_route_point(p_booking_id uuid, p_latitude double precision,
  p_longitude double precision, p_point_id uuid default gen_random_uuid())
returns void language sql set search_path = '' as $$
  select private.append_route_point(p_booking_id, p_latitude, p_longitude, p_point_id);
$$;
create function public.start_booking_session(p_booking_id uuid)
returns jsonb language sql set search_path = '' as $$
  select private.start_booking_session(p_booking_id);
$$;
create function public.complete_booking_session(p_booking_id uuid)
returns jsonb language sql set search_path = '' as $$
  select private.complete_booking_session(p_booking_id);
$$;

alter table public.profiles enable row level security;
alter table public.amigo_profiles enable row level security;
alter table public.verification_submissions enable row level security;
alter table public.favorites enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_messages enable row level security;
alter table public.booking_locations enable row level security;
alter table public.booking_route_recordings enable row level security;
alter table public.booking_route_points enable row level security;
alter table public.booking_sessions enable row level security;
alter table public.reviews enable row level security;

create policy profiles_owner_read on public.profiles for select to authenticated
using (id = (select auth.uid()));
create policy profiles_owner_edit on public.profiles for update to authenticated
using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy discoverable_amigos on public.amigo_profiles for select to authenticated
using ((verified and (not is_test or (select private.is_booking_demo_enabled()))) or id = (select private.my_amigo_id()));

create policy verification_owner_or_reviewer on public.verification_submissions for select to authenticated
using (traveler_id = (select auth.uid()) or (select private.is_verification_reviewer()));

create policy favorites_owner_read on public.favorites for select to authenticated
using (traveler_id = (select auth.uid()));
create policy favorites_owner_save on public.favorites for insert to authenticated with check (
  traveler_id = (select auth.uid()) and
  exists (select from public.amigo_profiles a where a.id = amigo_id)
);
create policy favorites_owner_remove on public.favorites for delete to authenticated
using (traveler_id = (select auth.uid()));

create policy bookings_participant_read on public.bookings for select to authenticated
using (traveler_id = (select auth.uid()) or amigo_id = (select private.my_amigo_id()));

create policy messages_participant_read on public.booking_messages for select to authenticated
using (exists (select from public.bookings b where b.id = booking_id and b.status in ('accepted', 'completed')));
create policy messages_participant_send on public.booking_messages for insert to authenticated
with check (not is_test and exists (
  select from public.bookings b where b.id = booking_id and b.status = 'accepted' and
  (sender_id = b.traveler_id and b.traveler_id = (select auth.uid()) or
   sender_id = b.amigo_id and b.amigo_id = (select private.my_amigo_id()))
));

create policy locations_participant_read on public.booking_locations for select to authenticated
using (
  updated_at > now() - interval '2 minutes' and
  exists (
    select from public.bookings b where b.id = booking_id and b.status = 'accepted'
      and now() between b.starts_at - interval '2 hours' and b.ends_at + interval '1 hour'
  )
);
create policy recording_owner_read on public.booking_route_recordings for select to authenticated
using (participant_id = (select auth.uid()) or participant_id = (select private.my_amigo_id()));
create policy route_participant_read on public.booking_route_points for select to authenticated
using (exists (select from public.bookings b where b.id = booking_id and b.status in ('accepted', 'completed')));
create policy sessions_participant_read on public.booking_sessions for select to authenticated
using (exists (select from public.bookings b where b.id = booking_id));

create policy published_reviews on public.reviews for select to authenticated
using (exists (select from public.amigo_profiles a where a.id = amigo_id));
create policy reviews_completed_booking on public.reviews for insert to authenticated
with check (
  traveler_id = (select auth.uid()) and
  exists (
    select from public.bookings b where b.id = reviews.booking_id and b.status = 'completed'
    and (b.traveler_id, b.amigo_id) = (reviews.traveler_id, reviews.amigo_id)
  )
);

revoke all on public.profiles, public.amigo_profiles, public.verification_submissions, public.favorites,
  public.bookings, public.booking_messages, public.booking_locations, public.booking_route_recordings,
  public.booking_route_points, public.booking_sessions, public.reviews from public, anon, authenticated, service_role;
grant select on public.profiles, public.amigo_profiles, public.verification_submissions, public.favorites,
  public.bookings, public.booking_messages, public.booking_locations, public.booking_route_recordings,
  public.booking_route_points, public.booking_sessions, public.reviews to authenticated;
grant update (display_name) on public.profiles to authenticated;
grant insert, delete on public.favorites to authenticated;
grant insert (id, booking_id, sender_id, body) on public.booking_messages to authenticated;
grant insert (booking_id, amigo_id, rating, body) on public.reviews to authenticated;
grant select, update on public.bookings to service_role;

revoke execute on function
  private.my_amigo_id(), private.is_booking_demo_enabled(), private.is_verification_reviewer(),
  private.submit_verification(uuid), private.review_verification(uuid, text, text),
  private.quote_booking(uuid, timestamptz, timestamptz),
  private.create_booking(uuid, timestamptz, timestamptz, text, double precision, double precision, text, uuid),
  private.respond_to_booking(uuid, text, text, boolean), private.cancel_booking(uuid),
  private.simulate_amigo_message(uuid, text),
  private.set_booking_location(uuid, double precision, double precision), private.set_route_recording(uuid, boolean),
  private.append_route_point(uuid, double precision, double precision, uuid),
  private.start_booking_session(uuid), private.complete_booking_session(uuid),
  public.is_booking_demo_enabled(), public.is_verification_reviewer(),
  public.submit_verification(uuid), public.review_verification(uuid, text, text),
  public.quote_booking(uuid, timestamptz, timestamptz),
  public.create_booking(uuid, timestamptz, timestamptz, text, double precision, double precision, text, uuid),
  public.respond_to_booking(uuid, text, text), public.simulate_amigo_response(uuid, text, text),
  public.cancel_booking(uuid), public.simulate_amigo_message(uuid, text),
  public.set_booking_location(uuid, double precision, double precision), public.set_route_recording(uuid, boolean),
  public.append_route_point(uuid, double precision, double precision, uuid),
  public.start_booking_session(uuid), public.complete_booking_session(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  private.my_amigo_id(), private.is_booking_demo_enabled(), private.is_verification_reviewer(),
  private.submit_verification(uuid), private.review_verification(uuid, text, text),
  private.quote_booking(uuid, timestamptz, timestamptz),
  private.create_booking(uuid, timestamptz, timestamptz, text, double precision, double precision, text, uuid),
  private.respond_to_booking(uuid, text, text, boolean), private.cancel_booking(uuid),
  private.simulate_amigo_message(uuid, text),
  private.set_booking_location(uuid, double precision, double precision), private.set_route_recording(uuid, boolean),
  private.append_route_point(uuid, double precision, double precision, uuid),
  private.start_booking_session(uuid), private.complete_booking_session(uuid),
  public.is_booking_demo_enabled(), public.is_verification_reviewer(),
  public.submit_verification(uuid), public.review_verification(uuid, text, text),
  public.quote_booking(uuid, timestamptz, timestamptz),
  public.create_booking(uuid, timestamptz, timestamptz, text, double precision, double precision, text, uuid),
  public.respond_to_booking(uuid, text, text), public.simulate_amigo_response(uuid, text, text),
  public.cancel_booking(uuid), public.simulate_amigo_message(uuid, text),
  public.set_booking_location(uuid, double precision, double precision), public.set_route_recording(uuid, boolean),
  public.append_route_point(uuid, double precision, double precision, uuid),
  public.start_booking_session(uuid), public.complete_booking_session(uuid)
to authenticated;

alter publication supabase_realtime add table public.verification_submissions, public.bookings,
  public.booking_messages, public.booking_locations, public.booking_route_recordings,
  public.booking_route_points, public.booking_sessions;
