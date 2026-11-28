begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select no_plan();

insert into auth.users (id, raw_user_meta_data) values
  ('712bfe78-897e-4963-b119-813a00e7a310', '{"display_name":"Verified Amigo","gomigo_role":"amigo"}'),
  ('712bfe78-897e-4963-b119-813a00e7a311', '{"display_name":"Unrelated Traveler"}');
insert into public.amigo_profiles (id, display_name, description, area, interests, age, gender, rate_centavos, verified)
values ('712bfe78-897e-4963-b119-813a00e7a312', 'Verified Amigo', 'Old short bio', 'Batangas',
  array['Legacy interest'], 40, 'woman', 50000, true);
insert into private.amigo_accounts (amigo_id, user_id) values
  ('712bfe78-897e-4963-b119-813a00e7a312','712bfe78-897e-4963-b119-813a00e7a310');
insert into storage.objects (bucket_id, name) values
  ('amigo-photos','712bfe78-897e-4963-b119-813a00e7a310/e8b2cf69-5186-42f0-9f4e-8342660ec1bf.png'),
  ('amigo-photos','712bfe78-897e-4963-b119-813a00e7a311/e8b2cf69-5186-42f0-9f4e-8342660ec1bf.png');

set local role authenticated;
set local request.jwt.claim.sub = '712bfe78-897e-4963-b119-813a00e7a310';
select is(public.update_amigo_profile('{"rate_centavos":62550}')->>'rate_centavos', '62550',
  'A legacy profile can save its rate without submitting a new bio or location');
select throws_ok(
  $$select public.update_amigo_profile('{"rate_centavos":25000.5}')$$,
  'P0001', 'Enter an hourly rate from PHP 200 to PHP 1,500 in whole centavos.', 'Reject fractional centavos'
);
select is(public.update_amigo_profile('{"interests":["Legacy interest","Photography"]}')->'interests',
  '["Legacy interest","Photography"]'::jsonb, 'Existing interests can be kept along with new choices');
select throws_ok(
  $$select public.update_amigo_profile('{"interests":["Invented interest"]}')$$,
  'P0001', 'Choose interests from the supplied options.', 'Reject arbitrary new interests'
);
select throws_ok(
  $$select public.update_amigo_profile('{"interests":[null]}')$$,
  'P0001', 'Choose interests from the supplied options.', 'Reject null interests'
);
select throws_ok(
  $$select public.update_amigo_profile('{"description":"Too short"}')$$,
  'P0001', 'Write at least 30 words and use up to 1,500 characters.', 'Validate the edited bio'
);
select is(public.update_amigo_profile(jsonb_build_object('description', repeat('word ', 30)))->>'description',
  btrim(repeat('word ', 30)), 'About You is persisted and returned');
select throws_ok(
  $$select public.update_amigo_profile('{"area":"Cebu"}')$$,
  'P0001', 'Set your service area from your current location.', 'Area and coordinates must change together'
);
select is(public.update_amigo_profile('{"area":"Cebu","discovery_latitude":10.3217,"discovery_longitude":123.8908}')
  ->>'discovery_latitude', '10.32', 'The saved public service area uses approximate coordinates');
select throws_ok(
  $$select public.update_amigo_profile('{"photo_path":"712bfe78-897e-4963-b119-813a00e7a311/e8b2cf69-5186-42f0-9f4e-8342660ec1bf.png"}')$$,
  '42501', 'Choose a photo uploaded by this Amigo.', 'Reject another account’s uploaded photo'
);
select is(public.update_amigo_profile('{"photo_path":"712bfe78-897e-4963-b119-813a00e7a310/e8b2cf69-5186-42f0-9f4e-8342660ec1bf.png"}')
  ->>'photo_path', '712bfe78-897e-4963-b119-813a00e7a310/e8b2cf69-5186-42f0-9f4e-8342660ec1bf.png',
  'An uploaded photo can be associated with its owner');
select throws_ok(
  $$select public.update_amigo_profile('{"display_name":"Overwritten name"}')$$,
  'P0001', 'Choose a supported profile field.', 'Verified identity is outside the update contract'
);

set local request.jwt.claim.sub = '712bfe78-897e-4963-b119-813a00e7a311';
select throws_ok(
  $$select public.update_amigo_profile('{"rate_centavos":40000}')$$,
  '42501', 'Sign in as a verified Amigo to edit your profile.', 'A Traveler cannot edit an Amigo profile'
);
select is((select rate_centavos from public.amigo_profiles where id = '712bfe78-897e-4963-b119-813a00e7a312'),
  62550, 'Traveler sees the persisted rate after subsequent independent profile edits');
select is((select display_name from public.amigo_profiles where id = '712bfe78-897e-4963-b119-813a00e7a312'),
  'Verified Amigo', 'Identity stays unchanged across individual profile edits');
select is((select interests from public.amigo_profiles where id = '712bfe78-897e-4963-b119-813a00e7a312'),
  array['Legacy interest','Photography'], 'Traveler sees the independently persisted interests');

reset role;
select * from finish();
rollback;
