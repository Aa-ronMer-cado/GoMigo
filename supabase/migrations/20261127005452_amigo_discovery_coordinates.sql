alter table public.amigo_profiles
  add column discovery_latitude double precision,
  add column discovery_longitude double precision,
  add constraint amigo_discovery_coordinate_pair check (
    (discovery_latitude is null and discovery_longitude is null) or (
      discovery_latitude is not null and discovery_longitude is not null and
      discovery_latitude between -90 and 90 and discovery_longitude between -180 and 180
    )
  );

comment on column public.amigo_profiles.discovery_latitude is
  'Approximate latitude in WGS 84 degrees for the Amigo''s public service area. Use a public place such as a city center.';
comment on column public.amigo_profiles.discovery_longitude is
  'Approximate longitude in WGS 84 degrees for the Amigo''s public service area. Use a public place such as a city center.';

-- Approximate GeoNames city centers for the three fictional demo profiles.
update public.amigo_profiles as amigo
set discovery_latitude = center.latitude, discovery_longitude = center.longitude
from (values
  ('ca980000-31d7-4d85-9cc7-e25de13a3001'::uuid, 10.3167, 123.8907), -- Cebu City
  ('ca980000-31d7-4d85-9cc7-e25de13a3002'::uuid, 9.7392, 118.7353), -- Puerto Princesa City
  ('ca980000-31d7-4d85-9cc7-e25de13a3003'::uuid, 14.6042, 120.9822) -- Manila
) as center(id, latitude, longitude)
where amigo.id = center.id and amigo.is_test;
