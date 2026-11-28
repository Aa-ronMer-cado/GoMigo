import 'package:amigo/features/verification/verification_repository.dart';
import 'package:amigo/features/verification/verification_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _approvedAsset = 'assets/figma/account/id_approved';

void main() {
  testWidgets(
    'renders changing approval GIF pixels on the verification screen',
    (tester) async {
      await tester.pumpWidget(_approvalScreen());
      final image = _approvalImage('gif');
      expect(image, findsOneWidget);
      final rawImage = find.descendant(
        of: image,
        matching: find.byType(RawImage),
      );

      Uint8List? firstFrame;
      var framesChanged = false;
      for (var attempt = 0; attempt < 30; attempt++) {
        // The Flutter engine decodes image frames outside the widget test clock.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 110));
        final frame = tester.widget<RawImage>(rawImage).image;
        if (frame == null) continue;
        final pixels = await tester.runAsync(() async {
          final bytes = await frame.toByteData();
          return bytes!.buffer.asUint8List();
        });
        if (firstFrame != null && !listEquals(pixels, firstFrame)) {
          framesChanged = true;
          break;
        }
        firstFrame ??= pixels;
      }

      expect(firstFrame, isNotNull);
      expect(framesChanged, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('uses still approval artwork with reduced motion enabled', (
    tester,
  ) async {
    await tester.pumpWidget(_approvalScreen(reduceMotion: true));
    expect(_approvalImage('png'), findsOneWidget);
    expect(_approvalImage('gif'), findsNothing);
  });
}

Finder _approvalImage(String extension) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == '$_approvedAsset.$extension',
);

Widget _approvalScreen({bool reduceMotion = false}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: AmigoVerificationScreen(
    repository: _UnusedVerificationRepository(),
    initialSubmission: const {
      'status': 'approved',
      'reviewed_display_name': 'Verified Amigo',
      'reviewed_gender': 'unspecified',
    },
  ),
);

class _UnusedVerificationRepository implements AmigoVerificationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
