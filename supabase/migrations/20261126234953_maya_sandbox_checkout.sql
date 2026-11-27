create table payments_private.maya_checkout_attempts (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  amount_centavos integer not null check (amount_centavos >= 100 and amount_centavos < 1000000000),
  status text not null default 'pending' check (status in ('pending', 'failed', 'cancelled', 'paid')),
  checkout_id uuid unique,
  checkout_url text check (
    checkout_url like 'https://payments-web-sandbox.maya.ph/%' or
    checkout_url like 'https://payments-web-sandbox.paymaya.com/%'
  ),
  created_at timestamptz not null default clock_timestamp(),
  paid_at timestamptz,
  check (checkout_url is null or checkout_id is not null),
  check (status in ('pending', 'cancelled') or checkout_id is not null),
  check ((status = 'paid') = (paid_at is not null))
);

create index maya_checkout_attempts_booking
  on payments_private.maya_checkout_attempts (booking_id, created_at desc);
create unique index maya_checkout_attempts_open_booking
  on payments_private.maya_checkout_attempts (booking_id) where status in ('pending', 'paid');

alter table payments_private.maya_checkout_attempts enable row level security;
revoke all on payments_private.maya_checkout_attempts from public, anon, authenticated, service_role;
grant select, insert, update on payments_private.maya_checkout_attempts to service_role;

create function public.maya_checkout_for_traveler(
  p_booking_id uuid, p_traveler_id uuid, p_create boolean
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  booking public.bookings;
  legacy_status text;
  attempt payments_private.maya_checkout_attempts;
  can_create boolean := false;
begin
  if p_create then
    select * into booking from public.bookings
    where id = p_booking_id and traveler_id = p_traveler_id for update;
  else
    select * into booking from public.bookings
    where id = p_booking_id and traveler_id = p_traveler_id;
  end if;
  if booking.id is null then
    raise exception 'Booking unavailable' using errcode = 'GM404';
  end if;

  select status into legacy_status from payments_private.checkout_attempts
  where booking_id = booking.id and status in ('pending', 'failed', 'paid');
  if found then
    if p_create and legacy_status <> 'paid' then
      raise exception 'The existing PayMongo test checkout must be resolved first' using errcode = 'GM409';
    end if;
    return jsonb_build_object('status', legacy_status, 'provider', 'paymongo', 'can_create', false);
  end if;

  select * into attempt from payments_private.maya_checkout_attempts
  where booking_id = booking.id
  order by (status in ('pending', 'paid')) desc, created_at desc, id desc limit 1;
  if p_create and booking.payment_status <> 'paid' and
    (attempt.id is null or attempt.status in ('failed', 'cancelled')) then
    if booking.status <> 'accepted' or booking.starts_at <= now() or booking.payment_status = 'pending' or
      booking.total_centavos < 100 or booking.total_centavos >= 1000000000 then
      raise exception 'Booking unavailable for test payment' using errcode = 'GM409';
    end if;
    -- Maya checkout creation has no documented idempotency guarantee. Only this caller may POST.
    insert into payments_private.maya_checkout_attempts (booking_id, amount_centavos)
    values (booking.id, booking.total_centavos) returning * into attempt;
    update public.bookings set payment_status = 'pending' where id = booking.id;
    can_create := true;
  end if;

  if attempt.id is null then
    return jsonb_build_object('status', booking.payment_status, 'provider', 'maya', 'can_create', false);
  end if;
  return to_jsonb(attempt) || jsonb_build_object('provider', 'maya', 'can_create', can_create);
end;
$$;

create function public.maya_save_checkout(
  p_attempt_id uuid, p_checkout_id text, p_checkout_url text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  attempt payments_private.maya_checkout_attempts;
  provider_id uuid := p_checkout_id::uuid;
begin
  update payments_private.maya_checkout_attempts as existing
  set checkout_id = provider_id, checkout_url = coalesce(existing.checkout_url, p_checkout_url)
  where existing.id = p_attempt_id and provider_id is not null
    and (existing.status = 'pending' or existing.checkout_id is not null)
    and (existing.checkout_id is null or existing.checkout_id = provider_id)
    and (existing.checkout_url is null or p_checkout_url is null or existing.checkout_url = p_checkout_url)
  returning * into attempt;
  if attempt.id is null then
    raise exception 'Checkout mismatch' using errcode = 'GM409';
  end if;
  return to_jsonb(attempt) || jsonb_build_object('provider', 'maya', 'can_create', false);
end;
$$;

create function public.maya_record_payment(
  p_attempt_id uuid, p_checkout_id text, p_status text,
  p_amount_centavos integer, p_currency text, p_payment_id text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  booking public.bookings;
  attempt payments_private.maya_checkout_attempts;
begin
  select b.* into booking from public.bookings b
  join payments_private.maya_checkout_attempts a on a.booking_id = b.id
  where a.id = p_attempt_id for update of b;
  if not found then
    return jsonb_build_object('status', 'unmatched');
  end if;
  select * into attempt from payments_private.maya_checkout_attempts where id = p_attempt_id for update;
  if p_status is null or p_status not in ('paid', 'failed', 'cancelled') or
    p_currency is distinct from 'PHP' or p_amount_centavos is distinct from attempt.amount_centavos or
    p_amount_centavos is distinct from booking.total_centavos or
    p_checkout_id is null or p_payment_id::uuid is distinct from p_checkout_id::uuid then
    raise exception 'Payment mismatch' using errcode = 'GM409';
  end if;
  if attempt.checkout_id is null then
    if attempt.status = 'pending' then
      return jsonb_build_object('status', 'unbound');
    end if;
    raise exception 'Payment mismatch' using errcode = 'GM409';
  end if;
  if attempt.checkout_id is distinct from p_checkout_id::uuid then
    raise exception 'Payment mismatch' using errcode = 'GM409';
  end if;
  if attempt.status = 'pending' then
    if booking.status <> 'accepted' or booking.payment_status <> 'pending' then
      raise exception 'Booking unavailable for payment settlement' using errcode = 'GM409';
    end if;
    update payments_private.maya_checkout_attempts
    set status = p_status, paid_at = case when p_status = 'paid' then clock_timestamp() end
    where id = attempt.id returning * into attempt;
    update public.bookings set payment_status = p_status where id = booking.id;
  end if;
  return to_jsonb(attempt) || jsonb_build_object('provider', 'maya', 'can_create', false);
end;
$$;

create function public.maya_release_uncreated(p_attempt_id uuid, p_definitive boolean)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  booking public.bookings;
  attempt payments_private.maya_checkout_attempts;
begin
  select b.* into booking from public.bookings b
  join payments_private.maya_checkout_attempts a on a.booking_id = b.id
  where a.id = p_attempt_id for update of b;
  if not found then
    return jsonb_build_object('status', 'unmatched');
  end if;
  select * into attempt from payments_private.maya_checkout_attempts where id = p_attempt_id for update;
  -- The service verifies rejection or empty RRN lookup. Keep ambiguous reservations through checkout expiry.
  if attempt.status = 'pending' and attempt.checkout_id is null and
    (p_definitive is true or attempt.created_at <= now() - interval '65 minutes') then
    if booking.status <> 'accepted' or booking.payment_status <> 'pending' then
      raise exception 'Booking unavailable for payment settlement' using errcode = 'GM409';
    end if;
    update payments_private.maya_checkout_attempts set status = 'cancelled'
    where id = attempt.id returning * into attempt;
    update public.bookings set payment_status = 'cancelled' where id = booking.id;
  end if;
  return to_jsonb(attempt) || jsonb_build_object('provider', 'maya', 'can_create', false);
end;
$$;

revoke execute on function public.maya_checkout_for_traveler(uuid, uuid, boolean),
  public.maya_save_checkout(uuid, text, text),
  public.maya_record_payment(uuid, text, text, integer, text, text),
  public.maya_release_uncreated(uuid, boolean)
from public, anon, authenticated, service_role;
grant execute on function public.maya_checkout_for_traveler(uuid, uuid, boolean),
  public.maya_save_checkout(uuid, text, text),
  public.maya_record_payment(uuid, text, text, integer, text, text),
  public.maya_release_uncreated(uuid, boolean)
to service_role;

create or replace function public.paymongo_checkout_for_traveler(
  p_booking_id uuid, p_traveler_id uuid, p_create boolean
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  booking public.bookings;
  attempt payments_private.checkout_attempts;
begin
  select * into booking from public.bookings where id = p_booking_id and traveler_id = p_traveler_id;
  if booking.id is null then
    raise exception 'Booking unavailable' using errcode = 'GM404';
  end if;
  select * into attempt from payments_private.checkout_attempts
  where booking_id = booking.id and status <> 'cancelled' and checkout_id is not null;
  if found then
    return to_jsonb(attempt);
  end if;
  if p_create then
    raise exception 'New PayMongo test checkouts are disabled' using errcode = 'GM409';
  end if;
  -- The old Edge function would create a PayMongo checkout if given an unbound reservation.
  return jsonb_build_object('status', booking.payment_status);
end;
$$;

create or replace function private.cancel_booking(p_booking_id uuid)
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
  if booking.payment_status = 'paid' then
    raise exception 'Contact GoMigo support about cancelling a paid booking.';
  end if;
  if booking.payment_status = 'pending' or exists (
    select from payments_private.checkout_attempts
    where booking_id = booking.id and status in ('pending', 'failed')
  ) then
    raise exception 'Cancel the open checkout before cancelling the booking.';
  end if;
  update public.bookings set status = 'cancelled'
  where id = p_booking_id returning * into booking;
  return to_jsonb(booking) - 'request_id';
end;
$$;
