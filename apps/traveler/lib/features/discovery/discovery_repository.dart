import 'package:supabase_flutter/supabase_flutter.dart';

class DiscoveryRepository {
  DiscoveryRepository(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> amigos() =>
      client.from('amigo_profiles').select().order('display_name');

  Future<Set<String>> favorites() async {
    final rows = await client
        .from('favorites')
        .select('amigo_id')
        .eq('traveler_id', client.auth.currentUser!.id);
    return rows.map((row) => row['amigo_id'] as String).toSet();
  }

  Future<void> setFavorite(String id, bool selected) async {
    final traveler = client.auth.currentUser!.id;
    if (selected) {
      await client.from('favorites').upsert({
        'traveler_id': traveler,
        'amigo_id': id,
      }, ignoreDuplicates: true);
    } else {
      await client
          .from('favorites')
          .delete()
          .eq('traveler_id', traveler)
          .eq('amigo_id', id);
    }
  }

  Future<List<Map<String, dynamic>>> reviews([String? amigo]) {
    final query = client
        .from('reviews')
        .select('amigo_id,rating,body,created_at');
    return (amigo == null ? query : query.eq('amigo_id', amigo)).order(
      'created_at',
      ascending: false,
    );
  }
}
