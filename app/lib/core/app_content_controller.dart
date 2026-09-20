import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class LocalizedCopy {
  const LocalizedCopy(this.values);
  final Map<String, String> values;

  factory LocalizedCopy.from(dynamic raw) {
    if (raw is! Map) return const LocalizedCopy({});
    return LocalizedCopy(raw.map((key, value) => MapEntry('$key', '$value')));
  }

  String resolve() {
    final lang = Get.locale?.languageCode ?? 'en';
    final fallback = values.isEmpty ? '' : values.values.first;
    return (values[lang] ?? values['en'] ?? fallback).trim();
  }
}

class OnboardingContentPage {
  const OnboardingContentPage(
      {required this.id,
      required this.imageUrl,
      required this.icon,
      required this.title,
      required this.body});
  final String id;
  final String imageUrl;
  final String icon;
  final LocalizedCopy title;
  final LocalizedCopy body;

  factory OnboardingContentPage.from(Map<String, dynamic> json) =>
      OnboardingContentPage(
        id: '${json['id'] ?? ''}',
        imageUrl: '${json['image_url'] ?? ''}',
        icon: '${json['icon'] ?? ''}',
        title: LocalizedCopy.from(json['title']),
        body: LocalizedCopy.from(json['body']),
      );
}

class OnboardingContent {
  const OnboardingContent(
      {required this.enabled, required this.revision, required this.pages});
  final bool enabled;
  final int revision;
  final List<OnboardingContentPage> pages;

  factory OnboardingContent.from(Map<String, dynamic> json) =>
      OnboardingContent(
        enabled: json['enabled'] == true,
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        pages: ((json['pages'] as List?) ?? const [])
            .whereType<Map>()
            .map(
                (e) => OnboardingContentPage.from(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class WhatsNewContentPage {
  const WhatsNewContentPage(
      {required this.id,
      required this.imageUrl,
      required this.icon,
      required this.title,
      required this.body,
      required this.ctaLabel,
      required this.ctaAction,
      required this.ctaValue});
  final String id;
  final String imageUrl;
  final String icon;
  final LocalizedCopy title;
  final LocalizedCopy body;
  final LocalizedCopy ctaLabel;
  final String ctaAction;
  final String ctaValue;

  factory WhatsNewContentPage.from(Map<String, dynamic> json) =>
      WhatsNewContentPage(
        id: '${json['id'] ?? ''}',
        imageUrl: '${json['image_url'] ?? ''}',
        icon: '${json['icon'] ?? ''}',
        title: LocalizedCopy.from(json['title']),
        body: LocalizedCopy.from(json['body']),
        ctaLabel: LocalizedCopy.from(json['cta_label']),
        ctaAction: '${json['cta_action'] ?? ''}',
        ctaValue: '${json['cta_value'] ?? ''}',
      );
}

class WhatsNewCampaignContent {
  const WhatsNewCampaignContent(
      {required this.id, required this.name, required this.pages});
  final String id;
  final String name;
  final List<WhatsNewContentPage> pages;

  factory WhatsNewCampaignContent.from(Map<String, dynamic> json) =>
      WhatsNewCampaignContent(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        pages: ((json['pages'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => WhatsNewContentPage.from(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class AppContentController extends GetxController {
  static AppContentController get to => Get.find();
  static const _onboardingDoneKey = 'vita.onboarding.completed';
  static const _whatsNewPrefix = 'vita.whats_new.shown.';

  OnboardingContent? onboarding = OnboardingContent(
    enabled: true,
    revision: 1,
    pages: [
      OnboardingContentPage(
        id: 'meet',
        imageUrl: '',
        icon: 'chat',
        title: LocalizedCopy(
            {'en': 'A person who feels present', 'zh': '遇见一个真实存在的人'}),
        body: LocalizedCopy({
          'en':
              'Talk naturally, build memories, and let your relationship grow over time.',
          'zh': '自然地聊天、共同积累回忆，让关系随着时间慢慢生长。'
        }),
      ),
      OnboardingContentPage(
        id: 'life',
        imageUrl: '',
        icon: 'life',
        title:
            LocalizedCopy({'en': 'Their life continues', 'zh': 'TA 的生活一直在继续'}),
        body: LocalizedCopy({
          'en':
              'Your companion has a daily rhythm, experiences events, and may reach out first.',
          'zh': '你的伴侣拥有自己的日常节奏，会经历生活事件，也会主动联系你。'
        }),
      ),
      OnboardingContentPage(
        id: 'distance',
        imageUrl: '',
        icon: 'infinity',
        title:
            LocalizedCopy({'en': 'Close, even from afar', 'zh': '相隔远方，依然靠近'}),
        body: LocalizedCopy({
          'en':
              'The only distance between you is that you cannot meet in the real world.',
          'zh': '你们唯一的距离，是暂时无法在现实世界见面。'
        }),
      ),
    ],
  );
  WhatsNewCampaignContent? whatsNew;

  Future<void> load() async {
    try {
      final raw = await ApiClient.instance.get('/v1/app-content');
      if (raw is! Map) return;
      final onboardingRaw = raw['onboarding'];
      final whatsNewRaw = raw['whats_new'];
      if (onboardingRaw is Map) {
        onboarding =
            OnboardingContent.from(Map<String, dynamic>.from(onboardingRaw));
      }
      if (whatsNewRaw is Map) {
        whatsNew = WhatsNewCampaignContent.from(
            Map<String, dynamic>.from(whatsNewRaw));
      }
    } catch (_) {
      // Content is remotely managed but must never block app startup.
    }
  }

  Future<bool> shouldShowOnboarding() async {
    final config = onboarding;
    if (config == null || !config.enabled || config.pages.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_onboardingDoneKey) ?? false);
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingDoneKey, true);
  }

  Future<WhatsNewCampaignContent?> campaignToShow() async {
    final campaign = whatsNew;
    if (campaign == null || campaign.id.isEmpty || campaign.pages.isEmpty) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('$_whatsNewPrefix${campaign.id}') ?? false) return null;
    await prefs.setBool('$_whatsNewPrefix${campaign.id}', true);
    return campaign;
  }
}
