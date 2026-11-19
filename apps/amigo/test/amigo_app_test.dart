import 'package:amigo/main.dart' as amigo;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomigo_shared_widgets/gomigo_shared_widgets.dart';

void main() {
  testWidgets('launches Amigo with the shared brand', (tester) async {
    amigo.main();
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'GoMigo Amigo',
    );
    expect(find.byType(GoMigoBrand), findsOneWidget);
    expect(find.text('Amigo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
