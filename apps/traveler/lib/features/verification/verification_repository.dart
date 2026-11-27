import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationRepository {
  VerificationRepository(this.client);
  final SupabaseClient client;

  Stream<List<Map<String, dynamic>>> submissions() => client
      .from('verification_submissions')
      .stream(primaryKey: ['id'])
      .eq('traveler_id', client.auth.currentUser!.id)
      .order('created_at', ascending: false);

  Future<void> upload(String submission, String side, Uint8List bytes) async {
    final mime = verificationImageType(bytes);
    if (mime == null || bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('Choose a JPG or PNG image of up to 8 MB.');
    }
    try {
      await client.storage
          .from('verification-ids')
          .uploadBinary(
            '${client.auth.currentUser!.id}/$submission/$side',
            bytes,
            fileOptions: FileOptions(contentType: mime, cacheControl: '0'),
          );
    } on StorageException catch (error) {
      // Retrying the exact same immutable object after a lost response.
      if (error.statusCode != '409') rethrow;
    }
  }

  Future<void> submit(String id) async {
    await client.rpc('submit_verification', params: {'p_submission_id': id});
  }
}

String? verificationImageType(Uint8List bytes) {
  if (bytes.length < 8) return null;
  if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff)
    return 'image/jpeg';
  const png = [137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < png.length; i++) {
    if (bytes[i] != png[i]) return null;
  }
  return 'image/png';
}
