import 'package:flutter_test/flutter_test.dart';
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
}
