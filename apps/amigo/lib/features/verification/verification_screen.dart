import 'package:gomigo_shared_widgets/verification.dart';

import 'verification_repository.dart';

class AmigoVerificationScreen extends IdVerificationScreen {
  const AmigoVerificationScreen({
    super.key,
    required AmigoVerificationRepository repository,
    super.onApproved,
    super.initialSubmission,
    super.onLogout,
  }) : super(repository: repository, needsReviewedDetails: true);
}
