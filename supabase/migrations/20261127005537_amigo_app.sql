alter table public.amigo_profiles
  add column photo_path text,
  add column available boolean not null default true;

create or replace function private.gomigo_create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  account_role text := case when new.raw_user_meta_data ->> 'gomigo_role' = 'amigo'
    then 'amigo' else 'traveler' end;
begin
  -- The signup choice sets an ordinary role once. Authorization reads profiles.
  insert into public.profiles (id, display_name, role)
  values (
    new.id,
    coalesce(nullif(left(btrim(new.raw_user_meta_data ->> 'display_name'), 80), ''),
      initcap(account_role)),
    account_role
  );
  return new;
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('amigo-photos', 'amigo-photos', true, 8388608, array['image/jpeg', 'image/png', 'image/webp']);

create policy gomigo_amigo_photo_owner_upload on storage.objects
for insert to authenticated with check (
  bucket_id = 'amigo-photos' and
  split_part(name, '/', 1) = (select auth.uid())::text and
  name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|png|webp)$' and
  exists (select from public.profiles where id = (select auth.uid()) and role = 'amigo')
);

alter policy gomigo_id_owner_upload on storage.objects with check (
  bucket_id = 'verification-ids' and
  split_part(name, '/', 1) = (select auth.uid())::text and
  name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/(front|back)$' and
  exists (select from public.profiles where id = (select auth.uid()) and role in ('traveler', 'amigo'))
);

alter table public.verification_submissions
  add column applicant_role text not null default 'traveler'
    check (applicant_role in ('traveler', 'amigo'));

create or replace function private.submit_verification(p_submission_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  applicant public.profiles%rowtype;
  submission public.verification_submissions%rowtype;
  object_prefix text;
begin
  select * into applicant from public.profiles where id = auth.uid() for update;
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

create function private.apply_amigo_id_approval()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Serialize approval with creation of the same account's discovery profile.
  perform from public.profiles where id = new.traveler_id for update;
  update public.amigo_profiles a
  set verified = true
  from private.amigo_accounts aa
  where aa.user_id = new.traveler_id and a.id = aa.amigo_id;
  return new;
end;
$$;
revoke execute on function private.apply_amigo_id_approval() from public, anon, authenticated, service_role;

create trigger apply_amigo_id_approval after update of status on public.verification_submissions
for each row when (
  new.applicant_role = 'amigo' and old.status = 'pending' and new.status = 'approved'
)
execute function private.apply_amigo_id_approval();

create function public.my_amigo_id()
returns uuid language sql stable set search_path = '' as $$
  select private.my_amigo_id();
$$;

create function private.save_amigo_profile(
  p_display_name text, p_description text, p_area text, p_languages text[], p_interests text[],
  p_age integer, p_gender text, p_rate_centavos integer, p_photo_path text,
  p_discovery_latitude double precision, p_discovery_longitude double precision
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  amigo public.amigo_profiles%rowtype;
  own_id uuid;
begin
  perform from public.profiles where id = actor and role = 'amigo' for update;
  if not found then
    raise exception 'Sign in as an Amigo to edit your profile.' using errcode = '42501';
  end if;
  if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 80 or
    p_description is null or char_length(btrim(p_description)) not between 1 and 1500 or
    p_area is null or char_length(btrim(p_area)) not between 1 and 160 or
    p_age is null or p_age not between 18 and 120 or
    p_gender is null or p_gender not in ('woman', 'man', 'nonbinary', 'unspecified') or
    p_rate_centavos is null or p_rate_centavos not between 10000 and 10000000 then
    raise exception 'Check your name, description, area, age, gender and hourly rate.';
  end if;
  if cardinality(p_languages) is null or cardinality(p_languages) not between 1 and 20 or
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

  own_id := private.my_amigo_id();
  if own_id is null then
    insert into public.amigo_profiles (
      display_name, description, area, languages, interests, age, gender, rate_centavos, photo_path,
      discovery_latitude, discovery_longitude, verified, available
    ) values (
      btrim(p_display_name), btrim(p_description), btrim(p_area), p_languages, p_interests, p_age,
      p_gender, p_rate_centavos, p_photo_path, p_discovery_latitude, p_discovery_longitude,
      exists (select from public.verification_submissions where traveler_id = actor and status = 'approved'),
      false
    ) returning * into amigo;
    insert into private.amigo_accounts (amigo_id, user_id) values (amigo.id, actor);
  else
    update public.amigo_profiles set display_name = btrim(p_display_name),
      description = btrim(p_description), area = btrim(p_area), languages = p_languages,
      interests = p_interests, age = p_age, gender = p_gender, rate_centavos = p_rate_centavos,
      photo_path = p_photo_path, discovery_latitude = p_discovery_latitude,
      discovery_longitude = p_discovery_longitude
    where id = own_id returning * into amigo;
  end if;
  update public.profiles set display_name = amigo.display_name where id = actor;
  return to_jsonb(amigo);
end;
$$;

create function public.save_amigo_profile(
  p_display_name text, p_description text, p_area text, p_languages text[], p_interests text[],
  p_age integer, p_gender text, p_rate_centavos integer, p_photo_path text default null,
  p_discovery_latitude double precision default null, p_discovery_longitude double precision default null
) returns jsonb language sql set search_path = '' as $$
  select private.save_amigo_profile(p_display_name, p_description, p_area, p_languages, p_interests,
    p_age, p_gender, p_rate_centavos, p_photo_path, p_discovery_latitude, p_discovery_longitude);
$$;

create function private.set_amigo_availability(p_available boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_available is null then
    raise exception 'Choose whether you are available.';
  end if;
  update public.amigo_profiles set available = p_available
  where id = (select private.my_amigo_id()) and (verified or not p_available);
  if not found then
    raise exception 'Complete your profile and ID verification before becoming available.' using errcode = '42501';
  end if;
  return p_available;
end;
$$;

create function public.set_amigo_availability(p_available boolean)
returns boolean language sql set search_path = '' as $$
  select private.set_amigo_availability(p_available);
$$;

create function private.get_amigo_booking_travelers(p_booking_ids uuid[])
returns table (booking_id uuid, display_name text, verified boolean)
language sql stable security definer set search_path = '' as $$
  select b.id, p.display_name, exists (
    select from public.verification_submissions v where v.traveler_id = b.traveler_id and v.status = 'approved'
  )
  from public.bookings b join public.profiles p on p.id = b.traveler_id
  where b.amigo_id = (select private.my_amigo_id()) and b.id = any(p_booking_ids);
$$;

create function public.get_amigo_booking_travelers(p_booking_ids uuid[])
returns table (booking_id uuid, display_name text, verified boolean)
language sql stable set search_path = '' as $$
  select * from private.get_amigo_booking_travelers(p_booking_ids);
$$;

alter policy favorites_owner_save on public.favorites with check (
  traveler_id = (select auth.uid()) and
  exists (select from public.profiles where id = (select auth.uid()) and role = 'traveler') and
  exists (select from public.amigo_profiles a where a.id = amigo_id)
);

create or replace function private.quote_booking(p_amigo_id uuid, p_starts_at timestamptz, p_ends_at timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  hourly_rate integer;
  subtotal integer;
begin
  if not exists (select from public.profiles where id = auth.uid() and role = 'traveler') then
    raise exception 'Sign in as a Traveler to request a quote.' using errcode = '42501';
  end if;
  if p_starts_at is null or p_ends_at is null or not isfinite(p_starts_at) or not isfinite(p_ends_at) or
    p_starts_at <= now() or p_ends_at - p_starts_at not between interval '1 minute' and interval '8 hours' then
    raise exception 'Choose a future booking lasting from 1 minute to 8 hours.';
  end if;
  select rate_centavos into hourly_rate from public.amigo_profiles
  where id = p_amigo_id and verified and available and (not is_test or private.is_booking_demo_enabled());
  if not found then
    raise exception 'This Amigo is unavailable.';
  end if;
  -- Preserve the shared demo rate calculation.
  subtotal := round(hourly_rate * extract(epoch from p_ends_at - p_starts_at) / 3600);
  return jsonb_build_object('subtotal_centavos', subtotal, 'fee_centavos', 0, 'total_centavos', subtotal);
end;
$$;

create or replace function private.respond_to_booking(p_booking_id uuid, p_decision text, p_reason text, simulate boolean)
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
  if p_decision = 'accepted' then
    -- This lock orders acceptance against the availability switch.
    perform from public.amigo_profiles where id = booking.amigo_id and verified and available for share;
    if not found then
      raise exception 'This Amigo is unavailable.';
    end if;
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

alter table public.reviews
  add column author_role text not null default 'traveler' check (author_role in ('traveler', 'amigo')),
  drop constraint reviews_booking_id_key,
  add unique (booking_id, author_role);

alter policy published_reviews on public.reviews using (
  (author_role = 'traveler' and exists (select from public.amigo_profiles a where a.id = amigo_id)) or
  (author_role = 'amigo' and (
    traveler_id = (select auth.uid()) or amigo_id = (select private.my_amigo_id())
  ))
);

alter policy reviews_completed_booking on public.reviews with check (
  author_role = 'traveler' and traveler_id = (select auth.uid()) and
  exists (
    select from public.bookings b where b.id = reviews.booking_id and b.status = 'completed'
      and (b.traveler_id, b.amigo_id) = (reviews.traveler_id, reviews.amigo_id)
  )
);

create function private.review_traveler(p_booking_id uuid, p_rating integer, p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings%rowtype;
  review public.reviews%rowtype;
  review_body text := nullif(btrim(p_body), '');
begin
  select * into booking from public.bookings
  where id = p_booking_id and amigo_id = (select private.my_amigo_id()) and status = 'completed'
  for update;
  if not found then
    raise exception 'Complete the booking as its Amigo before reviewing.' using errcode = '42501';
  end if;
  if p_rating is null or p_rating not between 1 and 5 or char_length(review_body) > 1000 then
    raise exception 'Choose a rating from 1 to 5 and use at most 1,000 characters.';
  end if;
  select * into review from public.reviews where booking_id = p_booking_id and author_role = 'amigo';
  if found then
    if review.rating = p_rating and review.body is not distinct from review_body then
      return to_jsonb(review);
    end if;
    raise exception 'You already reviewed this booking.';
  end if;
  insert into public.reviews (booking_id, traveler_id, amigo_id, rating, body, author_role)
  values (booking.id, booking.traveler_id, booking.amigo_id, p_rating, review_body, 'amigo')
  returning * into review;
  return to_jsonb(review);
end;
$$;

create function public.review_traveler(p_booking_id uuid, p_rating integer, p_body text default null)
returns jsonb language sql set search_path = '' as $$
  select private.review_traveler(p_booking_id, p_rating, p_body);
$$;

create table private.demo_amigo_payout_methods (
  amigo_id uuid primary key references public.amigo_profiles (id) on delete cascade,
  method text not null check (method in ('gcash', 'maya', 'bank')),
  label text not null check (char_length(btrim(label)) between 1 and 60)
);

create table private.demo_amigo_withdrawals (
  amigo_id uuid references public.amigo_profiles (id) on delete cascade,
  id uuid,
  amount_centavos integer not null check (amount_centavos > 0),
  created_at timestamptz not null default clock_timestamp(),
  primary key (amigo_id, id)
);

alter table private.demo_amigo_payout_methods enable row level security;
alter table private.demo_amigo_withdrawals enable row level security;
revoke all on private.demo_amigo_payout_methods, private.demo_amigo_withdrawals
from public, anon, authenticated, service_role;

create function private.completed_amigo_demo_earnings(p_amigo_id uuid)
returns table (booking_id uuid, completed_at timestamptz, amount_centavos integer, status text)
language sql stable set search_path = '' as $$
  select b.id, s.ended_at, b.subtotal_centavos, 'simulated'::text
  from public.bookings b join public.booking_sessions s on s.booking_id = b.id
  where b.amigo_id = p_amigo_id and b.status = 'completed' and b.payment_status = 'paid'
    and s.ended_at is not null;
$$;

create function private.get_demo_amigo_earnings()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  own_id uuid := private.my_amigo_id();
  earned bigint;
  withdrawn bigint;
  earnings jsonb;
  payout_method jsonb;
  withdrawals jsonb;
begin
  if own_id is null then
    raise exception 'An Amigo profile is required.' using errcode = '42501';
  end if;
  select coalesce(sum(e.amount_centavos), 0),
    coalesce(jsonb_agg(to_jsonb(e) order by e.completed_at desc, e.booking_id), '[]')
  into earned, earnings from private.completed_amigo_demo_earnings(own_id) e;
  select to_jsonb(p) - 'amigo_id' into payout_method
  from private.demo_amigo_payout_methods p where p.amigo_id = own_id;
  select coalesce(sum(w.amount_centavos), 0),
    coalesce(jsonb_agg((to_jsonb(w) - 'amigo_id') || jsonb_build_object('status', 'simulated')
      order by w.created_at desc, w.id), '[]')
  into withdrawn, withdrawals from private.demo_amigo_withdrawals w where w.amigo_id = own_id;
  return jsonb_build_object('available_centavos', earned - withdrawn, 'earnings', earnings,
    'payout_method', payout_method, 'withdrawals', withdrawals);
end;
$$;

create function public.get_demo_amigo_earnings()
returns jsonb language sql stable set search_path = '' as $$
  select private.get_demo_amigo_earnings();
$$;

create function private.save_demo_amigo_payout_method(p_method text, p_label text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  own_id uuid := private.my_amigo_id();
  label text := nullif(btrim(p_label), '');
begin
  if own_id is null then
    raise exception 'An Amigo profile is required.' using errcode = '42501';
  end if;
  if p_method is null or p_method not in ('gcash', 'maya', 'bank') or label is null or char_length(label) > 60 then
    raise exception 'Choose a demo payout method and enter a short fictional label.';
  end if;
  insert into private.demo_amigo_payout_methods (amigo_id, method, label)
  values (own_id, p_method, label)
  on conflict (amigo_id) do update set method = excluded.method, label = excluded.label;
  return jsonb_build_object('method', p_method, 'label', label);
end;
$$;

create function public.save_demo_amigo_payout_method(p_method text, p_label text)
returns jsonb language sql set search_path = '' as $$
  select private.save_demo_amigo_payout_method(p_method, p_label);
$$;

create function private.simulate_amigo_withdrawal(p_amount_centavos integer, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  own_id uuid := private.my_amigo_id();
  withdrawal private.demo_amigo_withdrawals%rowtype;
  balance bigint;
begin
  -- A single Amigo's withdrawal requests check and debit the same ledger in order.
  perform from public.amigo_profiles where id = own_id for update;
  if not found then
    raise exception 'An Amigo profile is required.' using errcode = '42501';
  end if;
  if p_request_id is null or p_amount_centavos is null or p_amount_centavos <= 0 then
    raise exception 'Enter a positive withdrawal amount.';
  end if;
  select * into withdrawal from private.demo_amigo_withdrawals where amigo_id = own_id and id = p_request_id;
  if found then
    if withdrawal.amount_centavos <> p_amount_centavos then
      raise exception 'Use a new request ID for a changed withdrawal amount.';
    end if;
  else
    if not exists (select from private.demo_amigo_payout_methods where amigo_id = own_id) then
      raise exception 'Set up a simulated payout method first.';
    end if;
    select
      (select coalesce(sum(amount_centavos), 0) from private.completed_amigo_demo_earnings(own_id)) -
      (select coalesce(sum(amount_centavos), 0) from private.demo_amigo_withdrawals where amigo_id = own_id)
    into balance;
    if p_amount_centavos > balance then
      raise exception 'The simulated balance is too low for this withdrawal.';
    end if;
    insert into private.demo_amigo_withdrawals (amigo_id, id, amount_centavos)
    values (own_id, p_request_id, p_amount_centavos)
    returning * into withdrawal;
  end if;
  return (to_jsonb(withdrawal) - 'amigo_id') || jsonb_build_object('status', 'simulated');
end;
$$;

create function public.simulate_amigo_withdrawal(p_amount_centavos integer, p_request_id uuid)
returns jsonb language sql set search_path = '' as $$
  select private.simulate_amigo_withdrawal(p_amount_centavos, p_request_id);
$$;

revoke execute on function private.completed_amigo_demo_earnings(uuid)
from public, anon, authenticated, service_role;

revoke execute on function
  public.my_amigo_id(),
  private.save_amigo_profile(text, text, text, text[], text[], integer, text, integer, text, double precision, double precision),
  public.save_amigo_profile(text, text, text, text[], text[], integer, text, integer, text, double precision, double precision),
  private.set_amigo_availability(boolean), public.set_amigo_availability(boolean),
  private.get_amigo_booking_travelers(uuid[]), public.get_amigo_booking_travelers(uuid[]),
  private.review_traveler(uuid, integer, text), public.review_traveler(uuid, integer, text),
  private.get_demo_amigo_earnings(), public.get_demo_amigo_earnings(),
  private.save_demo_amigo_payout_method(text, text), public.save_demo_amigo_payout_method(text, text),
  private.simulate_amigo_withdrawal(integer, uuid), public.simulate_amigo_withdrawal(integer, uuid)
from public, anon, authenticated, service_role;

grant execute on function
  public.my_amigo_id(),
  private.save_amigo_profile(text, text, text, text[], text[], integer, text, integer, text, double precision, double precision),
  public.save_amigo_profile(text, text, text, text[], text[], integer, text, integer, text, double precision, double precision),
  private.set_amigo_availability(boolean), public.set_amigo_availability(boolean),
  private.get_amigo_booking_travelers(uuid[]), public.get_amigo_booking_travelers(uuid[]),
  private.review_traveler(uuid, integer, text), public.review_traveler(uuid, integer, text),
  private.get_demo_amigo_earnings(), public.get_demo_amigo_earnings(),
  private.save_demo_amigo_payout_method(text, text), public.save_demo_amigo_payout_method(text, text),
  private.simulate_amigo_withdrawal(integer, uuid), public.simulate_amigo_withdrawal(integer, uuid)
to authenticated;
