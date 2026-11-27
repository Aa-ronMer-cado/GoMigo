begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(7);

insert into public.amigo_profiles (id, display_name, description, area, age, gender, rate_centavos, verified)
values ('fd650000-2b7a-43f1-8cde-c0061da0a003', 'Discovery fixture', 'Test profile', 'Cebu', 25, 'woman', 30000, true);

select ok(
  (select discovery_latitude is null and discovery_longitude is null from public.amigo_profiles
   where id = 'fd650000-2b7a-43f1-8cde-c0061da0a003'),
  'An older profile can leave both discovery coordinates unknown'
);
select throws_ok(
  $$update public.amigo_profiles set discovery_latitude = 10.3167 where id = 'fd650000-2b7a-43f1-8cde-c0061da0a003'$$,
  '23514', null, 'Latitude requires longitude'
);
select throws_ok(
  $$update public.amigo_profiles set discovery_longitude = 123.8907 where id = 'fd650000-2b7a-43f1-8cde-c0061da0a003'$$,
  '23514', null, 'Longitude requires latitude'
);
select throws_ok(
  $$update public.amigo_profiles set discovery_latitude = 91, discovery_longitude = 123.8907
    where id = 'fd650000-2b7a-43f1-8cde-c0061da0a003'$$,
  '23514', null, 'Latitude outside the geographic range is rejected'
);
select throws_ok(
  $$update public.amigo_profiles set discovery_latitude = 10.3167, discovery_longitude = -181
    where id = 'fd650000-2b7a-43f1-8cde-c0061da0a003'$$,
  '23514', null, 'Longitude outside the geographic range is rejected'
);
select throws_ok(
  $$update public.amigo_profiles set discovery_latitude = 'NaN', discovery_longitude = 123.8907
    where id = 'fd650000-2b7a-43f1-8cde-c0061da0a003'$$,
  '23514', null, 'Invalid numeric coordinates cannot masquerade as a position'
);

update public.amigo_profiles set discovery_latitude = 10.3167, discovery_longitude = 123.8907
where id = 'fd650000-2b7a-43f1-8cde-c0061da0a003';
insert into auth.users (id, raw_user_meta_data)
values ('fd650000-2b7a-43f1-8cde-c0061da0e005', '{"display_name":"Discovery Traveler"}');
set local role authenticated;
set local request.jwt.claim.sub = 'fd650000-2b7a-43f1-8cde-c0061da0e005';
select ok(
  (select discovery_latitude = 10.3167 and discovery_longitude = 123.8907 from public.amigo_profiles
   where id = 'fd650000-2b7a-43f1-8cde-c0061da0a003'),
  'A discoverable profile exposes its service-area coordinates under the existing read policy'
);

reset role;
select * from finish();
rollback;
