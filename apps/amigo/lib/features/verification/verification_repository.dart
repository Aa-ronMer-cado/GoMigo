import 'dart:typed_data';

import 'package:gomigo_shared_widgets/verification.dart';

class AmigoVerificationRepository extends IdVerificationRepository {
  const AmigoVerificationRepository(super.client);

  static String? imageType(Uint8List bytes) =>
      IdVerificationRepository.imageType(bytes);
}
