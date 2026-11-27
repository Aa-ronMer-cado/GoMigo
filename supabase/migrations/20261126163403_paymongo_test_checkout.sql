create schema payments_private;
revoke all on schema payments_private from public, anon, authenticated;
grant usage on schema payments_private to service_role;

create table payments_private.checkout_attempts (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  amount_centavos integer not null check (amount_centavos >= 100 and amount_centavos < 1000000000),
  status text not null default 'pending' check (status in ('pending', 'failed', 'cancelled', 'paid')),
  checkout_id text unique check (checkout_id ~ '^cs_[a-zA-Z0-9]+$'),
  checkout_url text check (checkout_url like 'https://checkout.paymongo.com/%'),
  paid_payment_id text unique check (paid_payment_id ~ '^pay_[a-zA-Z0-9]+$'),
  paid_event_id text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  check ((checkout_id is null) = (checkout_url is null)),
  check ((status = 'paid') = (paid_payment_id is not null and paid_event_id is not null and paid_at is not null))
);

create index checkout_attempts_booking on payments_private.checkout_attempts (booking_id);
create unique index checkout_attempts_open_booking
  on payments_private.checkout_attempts (booking_id) where status <> 'cancelled';

alter table payments_private.checkout_attempts enable row level security;
revoke all on payments_private.checkout_attempts from public, anon, authenticated;
grant select, insert, update on payments_private.checkout_attempts to service_role;
grant select on public.bookings to service_role;
grant update (payment_status) on public.bookings to service_role;

create function public.paymongo_checkout_for_traveler(
  p_booking_id uuid, p_traveler_id uuid, p_create boolean
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  booking public.bookings;
  attempt payments_private.checkout_attempts;
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

  select * into attempt from payments_private.checkout_attempts
  where booking_id = booking.id and status <> 'cancelled';

  if p_create and attempt.id is null and booking.payment_status <> 'paid' then
    if booking.status <> 'accepted' or booking.starts_at <= now() or
      booking.total_centavos < 100 or booking.total_centavos >= 1000000000 then
      raise exception 'Booking unavailable for test payment' using errcode = 'GM409';
    end if;
    insert into payments_private.checkout_attempts (booking_id, amount_centavos)
    values (booking.id, booking.total_centavos) returning * into attempt;
    update public.bookings set payment_status = 'pending' where id = booking.id;
  end if;

  if attempt.id is null then
    return jsonb_build_object('status', booking.payment_status);
  end if;
  return to_jsonb(attempt);
end;
$$;

create function public.paymongo_save_checkout(
  p_attempt_id uuid, p_checkout_id text, p_checkout_url text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  attempt payments_private.checkout_attempts;
begin
  update payments_private.checkout_attempts set
    checkout_id = p_checkout_id, checkout_url = p_checkout_url
  where id = p_attempt_id and checkout_id is null
    and p_checkout_id is not null and p_checkout_url is not null
  returning * into attempt;

  if attempt.id is null then
    select * into attempt from payments_private.checkout_attempts
    where id = p_attempt_id and checkout_id = p_checkout_id and checkout_url = p_checkout_url;
  end if;
  if attempt.id is null then
    raise exception 'Checkout mismatch' using errcode = 'GM409';
  end if;
  return to_jsonb(attempt);
end;
$$;

create function public.paymongo_refresh_checkout(
  p_attempt_id uuid, p_checkout_id text, p_status text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  attempt payments_private.checkout_attempts;
begin
  if p_status is null or p_status not in ('pending', 'failed', 'cancelled') then
    raise exception 'Invalid checkout status' using errcode = 'GM409';
  end if;
  perform b.id from public.bookings b join payments_private.checkout_attempts a on a.booking_id = b.id
  where a.id = p_attempt_id for update of b;
  select * into attempt from payments_private.checkout_attempts
  where id = p_attempt_id and checkout_id = p_checkout_id for update;
  if attempt.id is null then
    raise exception 'Checkout mismatch' using errcode = 'GM409';
  end if;

  if attempt.status in ('pending', 'failed') and attempt.status <> p_status then
    update payments_private.checkout_attempts set status = p_status
    where id = attempt.id returning * into attempt;
    update public.bookings set payment_status = p_status
    where id = attempt.booking_id;
  end if;
  return to_jsonb(attempt);
end;
$$;

create function public.paymongo_confirm_payment(
  p_event_id text, p_attempt_id uuid, p_checkout_id text, p_payment_id text, p_amount_centavos integer
) returns text language plpgsql security invoker set search_path = '' as $$
declare
  booking public.bookings;
  attempt payments_private.checkout_attempts;
begin
  select b.* into booking from public.bookings b
  join payments_private.checkout_attempts a on a.booking_id = b.id
  where a.id = p_attempt_id for update of b;
  select * into attempt from payments_private.checkout_attempts where id = p_attempt_id for update;

  if attempt.id is null then return 'ignored'; end if;
  if attempt.checkout_id is null then return 'retry'; end if;
  if attempt.checkout_id is distinct from p_checkout_id or
     attempt.amount_centavos is distinct from p_amount_centavos or
     booking.total_centavos is distinct from p_amount_centavos or
     p_payment_id is null or p_event_id is null then
    return 'mismatch';
  end if;
  if attempt.status = 'paid' then
    if attempt.paid_payment_id = p_payment_id then return 'duplicate'; end if;
    return 'mismatch';
  end if;
  if booking.status <> 'accepted' or attempt.status = 'cancelled' then return 'mismatch'; end if;

  update payments_private.checkout_attempts set
    status = 'paid', paid_payment_id = p_payment_id, paid_event_id = p_event_id, paid_at = now()
  where id = attempt.id;
  update public.bookings set payment_status = 'paid' where id = booking.id;
  return 'applied';
exception when unique_violation then
  return 'mismatch';
end;
$$;

revoke execute on function public.paymongo_checkout_for_traveler(uuid, uuid, boolean),
  public.paymongo_save_checkout(uuid, text, text),
  public.paymongo_refresh_checkout(uuid, text, text),
  public.paymongo_confirm_payment(text, uuid, text, text, integer) from public, anon, authenticated;

grant execute on function public.paymongo_checkout_for_traveler(uuid, uuid, boolean),
  public.paymongo_save_checkout(uuid, text, text),
  public.paymongo_refresh_checkout(uuid, text, text),
  public.paymongo_confirm_payment(text, uuid, text, text, integer) to service_role;
