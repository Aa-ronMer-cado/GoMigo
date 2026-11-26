insert into public.amigo_profiles (
  id, display_name, photo_url, description, area, languages, interests, age, gender,
  rate_centavos, verified, is_test, discovery_latitude, discovery_longitude
) values
  ('ca980000-31d7-4d85-9cc7-e25de13a3001', 'Demo • Dani Santos', 'demo-cebu',
   'Fictional profile for testing. Dani enjoys local food, city walks, and beach days.',
   'Cebu', array['Cebuano', 'English', 'Filipino'], array['Food trip', 'Walking', 'Beach'], 29, 'woman',
   30000, true, true, 10.3167, 123.8907),
  ('ca980000-31d7-4d85-9cc7-e25de13a3002', 'Demo • Nico Reyes', 'demo-palawan',
   'Fictional profile for testing. Nico likes kayaking and finding quiet spots for photos.',
   'Palawan', array['English', 'Filipino'], array['Kayaking', 'Photography', 'Beach'], 31, 'man',
   35000, true, true, 9.7392, 118.7353),
  ('ca980000-31d7-4d85-9cc7-e25de13a3003', 'Demo • Alex Cruz', 'demo-manila',
   'Fictional profile for testing. Alex enjoys museums, history, and exploring neighborhood cafes.',
   'Manila', array['English', 'Filipino'], array['Museums', 'History', 'Food trip'], 26, 'nonbinary',
   28000, true, true, 14.6042, 120.9822)
on conflict (id) do nothing;
