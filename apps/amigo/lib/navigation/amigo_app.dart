import 'package:flutter/material.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';

import '../features/booking/booking_declined_screen.dart';
import '../features/booking/booking_history_screen.dart';
import '../features/booking/user_booking_request_screen.dart';
import '../features/booking/user_pending_screen.dart';
import '../features/discovery/finding_migo_screen.dart';
import '../features/discovery/user_dashboard_screen.dart';
import '../features/discovery/view_migo_screen.dart';
import '../features/onboarding/location_required_screen.dart';
import '../features/onboarding/sign_up_screen.dart';
import '../features/onboarding/starting_page.dart';
import '../features/onboarding/temporary_login_screen.dart';
import '../features/onboarding/walkthrough_screen.dart';
import '../features/payment/card_details_first_setup_screen.dart';
import '../features/payment/card_details_second_setup_screen.dart';
import '../features/payment/payment_first_setup_screen.dart';
import '../features/payment/payment_second_setup_screen.dart';
import '../features/profile/card_details_profile_screen.dart';
import '../features/profile/payment_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/session/chat_box_screen.dart';
import '../features/session/complete_ratings_screen.dart';
import '../features/session/map_otw_screen.dart';
import '../features/session/timer_alert_screen.dart';
import '../features/session/timer_screen.dart';
import '../features/validation/capture_back_id_screen.dart';
import '../features/validation/capture_front_id_screen.dart';
import '../features/validation/upload_valid_id_screen.dart';
import 'amigo_routes.dart';

class GoMigoAmigoApp extends StatelessWidget {
  const GoMigoAmigoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GoMigo Amigo',
      theme: goMigoTheme(),
      initialRoute: AmigoRoutes.start,
      onGenerateRoute: (settings) {
        final Widget screen = switch (settings.name) {
          AmigoRoutes.start => const StartingPage(),
          AmigoRoutes.location => const LocationRequiredScreen(),
          AmigoRoutes.login => const TemporaryLoginScreen(),
          AmigoRoutes.signUp => const SignUpScreen(),
          AmigoRoutes.uploadValidId => const UploadValidIdScreen(),
          AmigoRoutes.walkthrough => const WalkthroughScreen(),
          AmigoRoutes.dashboard => const UserDashboardScreen(),
          AmigoRoutes.findingMigo => const FindingMigoScreen(),
          AmigoRoutes.viewMigo => const ViewMigoScreen(),
          AmigoRoutes.bookingRequest => const UserBookingRequestScreen(),
          AmigoRoutes.pending => const UserPendingScreen(),
          AmigoRoutes.declined => const BookingDeclinedScreen(),
          AmigoRoutes.mapOtw => const MapOtwScreen(),
          AmigoRoutes.chat => const ChatBoxScreen(),
          AmigoRoutes.profile => const ProfileScreen(),
          AmigoRoutes.paymentProfile => const PaymentProfileScreen(),
          AmigoRoutes.cardProfile => const CardDetailsProfileScreen(),
          AmigoRoutes.captureFront => const CaptureFrontIdScreen(),
          AmigoRoutes.captureBack => const CaptureBackIdScreen(),
          AmigoRoutes.paymentFirst => const PaymentFirstSetupScreen(),
          AmigoRoutes.cardFirst => const CardDetailsFirstSetupScreen(),
          AmigoRoutes.paymentSecond => const PaymentSecondSetupScreen(),
          AmigoRoutes.cardSecond => const CardDetailsSecondSetupScreen(),
          AmigoRoutes.historyAll =>
            const BookingHistoryScreen(status: BookingHistoryStatus.all),
          AmigoRoutes.historyAccepted =>
            const BookingHistoryScreen(status: BookingHistoryStatus.accepted),
          AmigoRoutes.historyDeclined =>
            const BookingHistoryScreen(status: BookingHistoryStatus.declined),
          AmigoRoutes.timer => const TimerScreen(),
          AmigoRoutes.timerAlert => const TimerAlertScreen(),
          AmigoRoutes.complete => const CompleteRatingsScreen(),
          _ => const StartingPage(),
        };
        return MaterialPageRoute<void>(
          builder: (_) => screen,
          settings: settings,
        );
      },
    );
  }
}
