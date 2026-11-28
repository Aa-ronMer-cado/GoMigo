import 'dart:typed_data';

import 'package:gomigo_shared_widgets/verification.dart';

String? verificationImageType(Uint8List bytes) =>
    IdVerificationRepository.imageType(bytes);
