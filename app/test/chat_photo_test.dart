import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:vita/core/theme.dart';
import 'package:vita/features/chat/chat_photo.dart';
import 'package:vita/shared/media_image.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('chat photo preserves full image and opens zoomable preview',
      (tester) async {
    Get.testMode = true;
    const url = 'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6rKsAAAAASUVORK5CYII=';
    await tester.pumpWidget(GetMaterialApp(
      theme: VitaTheme.light,
      home: const Scaffold(body: SizedBox(width: 240, child: ChatPhoto(url: url))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<VitaMediaImage>(find.byType(VitaMediaImage)).fit,
        BoxFit.contain);
    await tester.tap(find.byType(ChatPhoto));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatPhotoPreview), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final photo = find.descendant(
        of: find.byType(ChatPhotoPreview), matching: find.byType(VitaMediaImage));
    expect(tester.widget<VitaMediaImage>(photo).url, url);
    expect(tester.widget<VitaMediaImage>(photo).fit, BoxFit.contain);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChatPhotoPreview), findsNothing);
    expect(find.byType(ChatPhoto), findsOneWidget);
  });
}
