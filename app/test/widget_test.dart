import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vita/core/bootstrap.dart';
import 'package:vita/main.dart';

void main() {
  testWidgets('app boots to splash', (WidgetTester tester) async {
    WidgetsFlutterBinding.ensureInitialized();
    initControllers();

    await tester.pumpWidget(const VitaApp());

    // The splash screen shows the brand mark.
    expect(find.text('Vita'), findsWidgets);
    await tester.pumpAndSettle();
  });
}
