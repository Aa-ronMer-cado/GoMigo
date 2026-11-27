import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class AmigoVerificationRepository {
  const AmigoVerificationRepository(this.client);

  static const maxImageBytes = 8 * 1024 * 1024;
  final SupabaseClient client;

  String get _userId => client.auth.currentUser!.id;

  Future<Map<String, dynamic>?> approved() => client
      .from('verification_submissions')
      .select()
      .eq('traveler_id', _userId)
      .eq('status', 'approved')
      .maybeSingle();

  Stream<List<Map<String, dynamic>>> submissions() => client
      .from('verification_submissions')
      .stream(primaryKey: ['id'])
      .eq('traveler_id', _userId)
      .order('created_at', ascending: false);

  Future<void> submit(String id, Uint8List front, Uint8List back) async {
    final userId = _userId;
    await _upload('$userId/$id/front', front);
    await _upload('$userId/$id/back', back);
    await client.rpc('submit_verification', params: {'p_submission_id': id});
  }

  Future<void> _upload(String path, Uint8List bytes) async {
    final mime = imageType(bytes);
    if (mime == null || bytes.length > maxImageBytes) {
      throw const FormatException('Choose a JPG or PNG image of up to 8 MB.');
    }
    try {
      await client.storage
          .from('verification-ids')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, cacheControl: '0'),
          );
    } on StorageException catch (error) {
      // A lost response can leave this immutable upload on the server.
      final message = error.message.toLowerCase();
      if (error.statusCode != '409' &&
          !(error.statusCode == '400' && message.contains('already exists'))) {
        rethrow;
      }
    }
  }

  static String? imageType(Uint8List bytes) {
    if (bytes.length < 8) return null;
    if (bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
      return 'image/jpeg';
    }
    const png = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < png.length; i++) {
      if (bytes[i] != png[i]) return null;
    }
    return 'image/png';
  }
}
