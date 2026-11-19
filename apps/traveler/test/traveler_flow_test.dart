import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomigo_shared_widgets/gomigo_shared_widgets.dart';
import 'package:traveler/main.dart' as traveler;

void main() {
  testWidgets('launches Traveler and preserves onboarding and discovery', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Ahem, the widget test font, is wider than the runtime font.
    tester.platformDispatcher.textScaleFactorTestValue = 0.75;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    traveler.main();
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'GoMigo Traveler',
    );
    await tester.tap(find.byType(GoMigoBrand));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on location service'));
    await tester.pumpAndSettle();

    final signUp = find.text('Sign Up');
    await tester.ensureVisible(signUp);
    await tester.tap(signUp);
    await tester.pumpAndSettle();
    expect(find.text('Find a Local Buddy'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Book and Explore'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Travel with Confidence'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    final findAMigo = find.text('Find a Migo');
    await tester.tap(findAMigo);
    await tester.pumpAndSettle();
    expect(find.text('What do you want to do today?'), findsOneWidget);
    await tester.tap(find.text('Coffee & conversation').first);
    await tester.pumpAndSettle();
    expect(find.text('Food & hidden gems'), findsOneWidget);

    final discoveryBack = find.byWidgetPredicate(
      (widget) =>
          widget is SvgPicture &&
          widget.bytesLoader is SvgAssetLoader &&
          (widget.bytesLoader as SvgAssetLoader).assetName ==
              'assets/figma/finding_chevron_backward.svg',
    );
    await tester.tap(discoveryBack);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Find a Migo'), findsOneWidget);
  });
}
