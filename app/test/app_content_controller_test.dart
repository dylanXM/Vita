import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vita/core/app_content_controller.dart';

void main() {
  test('social media links are trimmed and expose their visibility state', () {
    final links = SocialMediaLinks.from({
      'social_instagram_url': ' https://instagram.com/vita ',
      'social_tiktok_url': '',
      'social_x_url': 'https://x.com/vita',
      'social_discord_url': null,
    });

    expect(links.instagramUrl, 'https://instagram.com/vita');
    expect(links.xUrl, 'https://x.com/vita');
    expect(links.tiktokUrl, isEmpty);
    expect(links.discordUrl, isEmpty);
    expect(links.isEmpty, isFalse);
    expect(const SocialMediaLinks().isEmpty, isTrue);
  });
  testWidgets(
      'content requests coalesce and a withdrawn campaign clears old content',
      (tester) async {
    var calls = 0;
    final gate = Completer<dynamic>();
    final controller = AppContentController(fetchContent: () {
      calls++;
      return calls == 1 ? gate.future : Future.value({'whats_new': null});
    });
    final first = controller.synchronize();
    final second = controller.synchronize();
    expect(calls, 1);
    gate.complete({
      'whats_new': {
        'id': 'campaign',
        'name': 'update',
        'updated_at': '1',
        'pages': [
          {
            'id': 'one',
            'title': {'en': 'Hello'},
            'body': {'en': 'World'}
          }
        ]
      }
    });
    await Future.wait([first, second]);
    expect(controller.whatsNew?.id, 'campaign');
    await controller.synchronize();
    expect(controller.whatsNew, isNull);
  });

  testWidgets('changed revision of the same campaign can be shown once again',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var version = '1';
    final controller = AppContentController(
        fetchContent: () async => {
              'whats_new': {
                'id': 'campaign',
                'name': 'update',
                'updated_at': version,
                'pages': [
                  {
                    'id': 'one',
                    'title': {'en': 'Hello'},
                    'body': {'en': 'World'}
                  }
                ]
              }
            });
    await controller.synchronize();
    expect(await controller.campaignToShow(), isNotNull);
    expect(await controller.campaignToShow(), isNull);
    version = '2';
    await controller.synchronize();
    expect(await controller.campaignToShow(), isNotNull);
    expect(await controller.campaignToShow(), isNull);
  });
}
