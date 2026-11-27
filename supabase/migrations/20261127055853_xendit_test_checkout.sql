create table payments_private.xendit_checkout_attempts (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  amount_centavos integer not null check (amount_centavos >= 100 and amount_centavos < 1000000000),
  status text not null default 'pending' check (status in ('pending', 'failed', 'cancelled', 'paid')),
  checkout_id text unique check (checkout_id is null or checkout_id ~ '^ps-[a-zA-Z0-9]{24}$'),
  checkout_url text check (checkout_url is null or checkout_url like 'https://checkout-staging.xendit.co/%' or checkout_url like 'https://dev.xen.to/%'),
  created_at timestamptz not null default clock_timestamp(),
  paid_at timestamptz,
  check (checkout_url is null or checkout_id is not null),
  check ((status = 'paid') = (paid_at is not null))
);

create index xendit_checkout_attempts_booking on payments_private.xendit_checkout_attempts (booking_id, created_at desc);
create unique index xendit_checkout_attempts_open on payments_private.xendit_checkout_attempts (booking_id) where status in ('pending', 'paid');
alter table payments_private.xendit_checkout_attempts enable row level security;
revoke all on payments_private.xendit_checkout_attempts from public, anon, authenticated, service_role;
grant select, insert, update on payments_private.xendit_checkout_attempts to service_role;

-- Older deployed clients can reconcile existing Maya attempts, but cannot create new ones.
create function payments_private.stop_new_maya_checkout() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'New Maya checkouts are disabled' using errcode = 'GM409';
end;
$$;
create trigger stop_new_maya_checkout before insert on payments_private.maya_checkout_attempts
for each row execute function payments_private.stop_new_maya_checkout();

create function public.xendit_checkout_for_traveler(p_booking_id uuid, p_traveler_id uuid, p_create boolean)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  booking public.bookings;
  attempt payments_private.xendit_checkout_attempts;
  legacy_status text;
  can_create boolean := false;
begin
  select * into booking from public.bookings
  where id = p_booking_id and traveler_id = p_traveler_id for update;
  if booking.id is null then raise exception 'Booking unavailable' using errcode = 'GM404'; end if;

  select status into legacy_status from payments_private.checkout_attempts
  where booking_id = booking.id and status in ('pending', 'failed', 'paid') limit 1;
  if found then return jsonb_build_object('provider', 'paymongo', 'status', legacy_status, 'can_create', false); end if;
  select status into legacy_status from payments_private.maya_checkout_attempts
  where booking_id = booking.id and status in ('pending', 'paid') limit 1;
  if found then return jsonb_build_object('provider', 'maya', 'status', legacy_status, 'can_create', false); end if;

  select * into attempt from payments_private.xendit_checkout_attempts
  where booking_id = booking.id order by (status in ('pending', 'paid')) desc, created_at desc, id desc limit 1;
  if p_create and booking.payment_status <> 'paid' and (attempt.id is null or attempt.status in ('failed', 'cancelled')) then
    if booking.status <> 'accepted' or booking.starts_at <= now() or booking.payment_status = 'pending' then
      raise exception 'Booking unavailable for test payment' using errcode = 'GM409';
    end if;
    insert into payments_private.xendit_checkout_attempts (booking_id, amount_centavos)
    values (booking.id, booking.total_centavos) returning * into attempt;
    update public.bookings set payment_status = 'pending' where id = booking.id;
    can_create := true;
  end if;
  if attempt.id is null then
    return jsonb_build_object('provider', 'xendit', 'status', booking.payment_status, 'can_create', false);
  end if;
  return to_jsonb(attempt) || jsonb_build_object('provider', 'xendit', 'can_create', can_create);
end;
$$;

create function public.xendit_bind_checkout(p_attempt_id uuid, p_checkout_id text, p_checkout_url text, p_amount_centavos integer)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare attempt payments_private.xendit_checkout_attempts;
begin
  update payments_private.xendit_checkout_attempts as existing
  set checkout_id = p_checkout_id, checkout_url = coalesce(existing.checkout_url, p_checkout_url)
  where existing.id = p_attempt_id and p_checkout_id ~ '^ps-[a-zA-Z0-9]{24}$'
    and existing.amount_centavos = p_amount_centavos
    and (existing.status = 'pending' or existing.checkout_id is not null)
    and (existing.checkout_id is null or existing.checkout_id = p_checkout_id)
    and (existing.checkout_url is null or p_checkout_url is null or existing.checkout_url = p_checkout_url)
  returning * into attempt;
  if attempt.id is null then raise exception 'Checkout mismatch' using errcode = 'GM409'; end if;
  return to_jsonb(attempt) || jsonb_build_object('provider', 'xendit', 'can_create', false);
end;
$$;

create function public.xendit_record_payment(p_attempt_id uuid, p_checkout_id text, p_status text, p_amount_centavos integer, p_currency text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare booking public.bookings; attempt payments_private.xendit_checkout_attempts;
begin
  select b.* into booking from public.bookings b join payments_private.xendit_checkout_attempts a on a.booking_id = b.id
  where a.id = p_attempt_id for update of b;
  if not found then return jsonb_build_object('status', 'unmatched'); end if;
  select * into attempt from payments_private.xendit_checkout_attempts where id = p_attempt_id for update;
  if p_status is null or p_status not in ('paid', 'failed', 'cancelled') or p_currency is distinct from 'PHP'
    or p_amount_centavos is distinct from attempt.amount_centavos or p_amount_centavos is distinct from booking.total_centavos
    or p_checkout_id is null or attempt.checkout_id is null or p_checkout_id is distinct from attempt.checkout_id then
    raise exception 'Payment mismatch' using errcode = 'GM409';
  end if;
  if attempt.status = 'pending' then
    if booking.status <> 'accepted' or booking.payment_status <> 'pending' then
      raise exception 'Booking unavailable for payment settlement' using errcode = 'GM409';
    end if;
    update payments_private.xendit_checkout_attempts set status = p_status,
      paid_at = case when p_status = 'paid' then clock_timestamp() end where id = attempt.id returning * into attempt;
    update public.bookings set payment_status = p_status where id = booking.id;
  end if;
  return to_jsonb(attempt) || jsonb_build_object('provider', 'xendit', 'can_create', false);
end;
$$;

create function public.xendit_release_rejected(p_attempt_id uuid)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare booking public.bookings; attempt payments_private.xendit_checkout_attempts;
begin
  select b.* into booking from public.bookings b join payments_private.xendit_checkout_attempts a on a.booking_id = b.id
  where a.id = p_attempt_id for update of b;
  if not found then return jsonb_build_object('status', 'unmatched'); end if;
  select * into attempt from payments_private.xendit_checkout_attempts where id = p_attempt_id for update;
  if attempt.status = 'pending' and attempt.checkout_id is null then
    if booking.status <> 'accepted' or booking.payment_status <> 'pending' then
      raise exception 'Booking unavailable for payment settlement' using errcode = 'GM409';
    end if;
    update payments_private.xendit_checkout_attempts set status = 'cancelled' where id = attempt.id returning * into attempt;
    update public.bookings set payment_status = 'cancelled' where id = booking.id;
  end if;
  return to_jsonb(attempt) || jsonb_build_object('provider', 'xendit', 'can_create', false);
end;
$$;

revoke execute on function public.xendit_checkout_for_traveler(uuid,uuid,boolean), public.xendit_bind_checkout(uuid,text,text,integer),
  public.xendit_record_payment(uuid,text,text,integer,text), public.xendit_release_rejected(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.xendit_checkout_for_traveler(uuid,uuid,boolean), public.xendit_bind_checkout(uuid,text,text,integer),
  public.xendit_record_payment(uuid,text,text,integer,text), public.xendit_release_rejected(uuid) to service_role;
