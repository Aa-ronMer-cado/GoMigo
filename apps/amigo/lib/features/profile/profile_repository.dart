import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AmigoProfileRepository {
  const AmigoProfileRepository(this.client);

  static const maxPhotoBytes = 8 * 1024 * 1024;
  final SupabaseClient client;

  Future<Map<String, dynamic>?> profile() async {
    final id = await client.rpc('my_amigo_id') as String?;
    if (id == null) return null;
    return client.from('amigo_profiles').select().eq('id', id).single();
  }

  Future<List<Map<String, dynamic>>> receivedReviews(String amigoId) => client
      .from('reviews')
      .select('rating,body,created_at')
      .eq('amigo_id', amigoId)
      .eq('author_role', 'traveler')
      .order('created_at', ascending: false);

  String? photoUrl(Map<String, dynamic>? profile) {
    final path = profile?['photo_path'] as String?;
    if (path != null) {
      return client.storage.from('amigo-photos').getPublicUrl(path);
    }
    return profile?['photo_url'] as String?;
  }

  Future<String> uploadPhoto(Uint8List bytes, String mime) async {
    final extension = mime == 'image/png' ? 'png' : 'jpg';
    final path =
        '${client.auth.currentUser!.id}/${const Uuid().v4()}.$extension';
    await client.storage
        .from('amigo-photos')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    return path;
  }

  Future<void> save({
    required String description,
    required String area,
    required List<String> interests,
    required int rateCentavos,
    required String? photoPath,
    required double latitude,
    required double longitude,
  }) async {
    await client.rpc(
      'save_amigo_profile',
      params: {
        'p_display_name': null,
        'p_description': description,
        'p_area': area,
        'p_languages': null,
        'p_interests': interests,
        'p_age': null,
        'p_gender': null,
        'p_rate_centavos': rateCentavos,
        'p_photo_path': photoPath,
        'p_discovery_latitude': latitude,
        'p_discovery_longitude': longitude,
      },
    );
  }
}
