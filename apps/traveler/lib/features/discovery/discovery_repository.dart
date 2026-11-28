import 'package:supabase_flutter/supabase_flutter.dart';

import 'amigo_photo.dart';

class DiscoveryRepository {
  DiscoveryRepository(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> amigos() async {
    final rows = await client
        .from('amigo_profiles')
        .select()
        .eq('verified', true)
        .eq('available', true)
        .order('display_name');
    return rows.map((row) => resolveAmigoPhoto(client, row)).toList();
  }

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

  Future<List<Map<String, dynamic>>> reviews([String? amigo]) async {
    final query = client.from('reviews').select();
    final rows = await (amigo == null ? query : query.eq('amigo_id', amigo))
        .order('created_at', ascending: false);
    return rows.where((row) => row['author_role'] != 'amigo').toList();
  }
}
