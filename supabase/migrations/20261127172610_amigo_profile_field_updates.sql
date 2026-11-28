create function private.update_amigo_profile(p_changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  profile public.amigo_profiles%rowtype;
  new_description text;
  new_interests text[];
  new_rate numeric;
  new_photo_path text;
  new_area text;
  new_latitude numeric;
  new_longitude numeric;
  allowed_interests constant text[] := array[
    'Food & Dining', 'Nature & Adventure', 'Shopping', 'Photography',
    'Nightlife', 'Local Culture', 'Arts & Museums', 'Outdoor Activities', 'Local Experiences'
  ];
begin
  select * into profile
  from public.amigo_profiles
  where id = (select private.my_amigo_id()) and verified
  for update;
  if not found then
    raise exception 'Sign in as a verified Amigo to edit your profile.' using errcode = '42501';
  end if;

  if jsonb_typeof(p_changes) is distinct from 'object' or p_changes = '{}'::jsonb
    or p_changes - array[
      'description', 'interests', 'rate_centavos', 'photo_path',
      'area', 'discovery_latitude', 'discovery_longitude'
    ] <> '{}'::jsonb then
    raise exception 'Choose a supported profile field.';
  end if;

  if p_changes ? 'description' then
    new_description := btrim(p_changes ->> 'description');
    if jsonb_typeof(p_changes -> 'description') is distinct from 'string'
      or char_length(new_description) > 1500
      or regexp_count(new_description, '[^[:space:]]+') < 30 then
      raise exception 'Write at least 30 words and use up to 1,500 characters.';
    end if;
  end if;

  if p_changes ? 'interests' then
    if jsonb_typeof(p_changes -> 'interests') is distinct from 'array' then
      raise exception 'Choose interests from the supplied options.';
    end if;
    if jsonb_array_length(p_changes -> 'interests') > 20 or exists (
      select from jsonb_array_elements(p_changes -> 'interests') as item
      where jsonb_typeof(item) <> 'string'
    ) then
      raise exception 'Choose interests from the supplied options.';
    end if;
    select array(select jsonb_array_elements_text(p_changes -> 'interests')) into new_interests;
    if not (new_interests <@ (allowed_interests || coalesce(profile.interests, '{}'))) then
      raise exception 'Choose interests from the supplied options.';
    end if;
  end if;

  if p_changes ? 'rate_centavos' then
    if jsonb_typeof(p_changes -> 'rate_centavos') is distinct from 'number' then
      raise exception 'Enter an hourly rate from PHP 200 to PHP 1,500.';
    end if;
    new_rate := (p_changes ->> 'rate_centavos')::numeric;
    if new_rate not between 20000 and 150000 or new_rate <> trunc(new_rate) then
      raise exception 'Enter an hourly rate from PHP 200 to PHP 1,500 in whole centavos.';
    end if;
  end if;

  if p_changes ? 'photo_path' then
    new_photo_path := p_changes ->> 'photo_path';
    if jsonb_typeof(p_changes -> 'photo_path') is distinct from 'string'
      or split_part(new_photo_path, '/', 1) <> actor::text
      or not exists (select from storage.objects where bucket_id = 'amigo-photos' and name = new_photo_path) then
      raise exception 'Choose a photo uploaded by this Amigo.' using errcode = '42501';
    end if;
  end if;

  if p_changes ?| array['area', 'discovery_latitude', 'discovery_longitude'] then
    new_area := btrim(p_changes ->> 'area');
    if jsonb_typeof(p_changes -> 'area') is distinct from 'string'
      or char_length(new_area) not between 1 and 160
      or jsonb_typeof(p_changes -> 'discovery_latitude') is distinct from 'number'
      or jsonb_typeof(p_changes -> 'discovery_longitude') is distinct from 'number' then
      raise exception 'Set your service area from your current location.';
    end if;
    new_latitude := (p_changes ->> 'discovery_latitude')::numeric;
    new_longitude := (p_changes ->> 'discovery_longitude')::numeric;
    if new_latitude not between -90 and 90 or new_longitude not between -180 and 180 then
      raise exception 'Choose valid public service area coordinates.';
    end if;
  end if;

  update public.amigo_profiles
  set description = coalesce(new_description, description),
      interests = coalesce(new_interests, interests),
      rate_centavos = coalesce(new_rate::integer, rate_centavos),
      photo_path = coalesce(new_photo_path, photo_path),
      area = coalesce(new_area, area),
      discovery_latitude = coalesce(round(new_latitude, 2)::double precision, discovery_latitude),
      discovery_longitude = coalesce(round(new_longitude, 2)::double precision, discovery_longitude)
  where id = profile.id
  returning * into profile;

  return to_jsonb(profile);
end;
$$;

create function public.update_amigo_profile(p_changes jsonb)
returns jsonb
language sql
set search_path = ''
as $$
  select private.update_amigo_profile(p_changes);
$$;

revoke execute on function private.update_amigo_profile(jsonb), public.update_amigo_profile(jsonb)
from public, anon, authenticated, service_role;
grant execute on function private.update_amigo_profile(jsonb), public.update_amigo_profile(jsonb)
to authenticated;
