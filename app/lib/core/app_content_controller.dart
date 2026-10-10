import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'legal_documents.dart';

class LocalizedCopy {
  const LocalizedCopy(this.values);
  final Map<String, String> values;

  factory LocalizedCopy.from(dynamic raw) {
    if (raw is! Map) return const LocalizedCopy({});
    return LocalizedCopy(raw.map((key, value) => MapEntry('$key', '$value')));
  }

  String resolve() {
    final locale = Get.locale;
    final lang = locale?.languageCode ?? 'en';
    final regional =
        locale?.countryCode == null ? null : '${lang}_${locale!.countryCode}';
    final fallback = values.isEmpty ? '' : values.values.first;
    return (values[regional] ?? values[lang] ?? values['en'] ?? fallback)
        .trim();
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

class SocialMediaLinks {
  const SocialMediaLinks({
    this.instagramUrl = '',
    this.tiktokUrl = '',
    this.xUrl = '',
    this.discordUrl = '',
  });

  final String instagramUrl;
  final String tiktokUrl;
  final String xUrl;
  final String discordUrl;

  bool get isEmpty =>
      instagramUrl.isEmpty &&
      tiktokUrl.isEmpty &&
      xUrl.isEmpty &&
      discordUrl.isEmpty;

  factory SocialMediaLinks.from(Map<String, dynamic> json) => SocialMediaLinks(
        instagramUrl: '${json['social_instagram_url'] ?? ''}'.trim(),
        tiktokUrl: '${json['social_tiktok_url'] ?? ''}'.trim(),
        xUrl: '${json['social_x_url'] ?? ''}'.trim(),
        discordUrl: '${json['social_discord_url'] ?? ''}'.trim(),
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
        title: LocalizedCopy({
          'en': 'Meet an AI companion with a life of their own',
          'zh': '遇见有自己日常的 AI 伴侣',
          'zh_TW': '遇見有自己日常的 AI 伴侶',
          'es': 'Conoce a un compañero de IA con vida propia',
          'pt': 'Conheça um companheiro de IA com vida própria',
          'ja': '自分の日常を持つAIコンパニオンと出会う',
          'ko': '자신만의 일상을 가진 AI 동반자를 만나보세요',
          'ar': 'تعرّف على رفيق ذكاء اصطناعي له حياته الخاصة',
        }),
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
        title: LocalizedCopy({
          'en': 'More than a chat',
          'zh': '不止于聊天',
          'zh_TW': '不止於聊天',
          'es': 'Más que una conversación',
          'pt': 'Mais que uma conversa',
          'ja': '会話だけではない体験',
          'ko': '대화 그 이상의 경험',
          'ar': 'أكثر من مجرد محادثة',
        }),
        body: LocalizedCopy({
          'en':
              'Begin with a conversation and a visit. The full experience adds a daily rhythm, life events, and messages your companion initiates.',
          'zh': '从一次对话和拜访开始；解锁完整体验后，TA 会拥有日常节奏、生活事件，也会主动联系你。',
          'zh_TW': '從一次對話和拜訪開始；解鎖完整體驗後，TA 會擁有日常節奏、生活事件，也會主動聯繫你。',
          'es':
              'Empieza con una charla y una visita. La experiencia completa añade una rutina, eventos y mensajes iniciados por tu compañero.',
          'pt':
              'Comece com uma conversa e uma visita. A experiência completa inclui uma rotina, acontecimentos e mensagens iniciadas pelo seu companheiro.',
          'ja': '会話と訪問から始めましょう。フル体験では、日々の暮らしや出来事、コンパニオンからの連絡が加わります。',
          'ko': '대화와 방문으로 시작하세요. 전체 경험에서는 동반자의 일상과 사건, 먼저 보내는 메시지가 더해집니다.',
          'ar':
              'ابدأ بمحادثة وزيارة. تضيف التجربة الكاملة حياة يومية وأحداثًا ورسائل يبدأها رفيقك.',
        }),
      ),
      OnboardingContentPage(
        id: 'distance',
        imageUrl: '',
        icon: 'infinity',
        title: LocalizedCopy({
          'en': 'Moments worth remembering',
          'zh': '值得记住的相处',
          'zh_TW': '值得記住的相處',
          'es': 'Momentos que vale la pena recordar',
          'pt': 'Momentos que valem a pena lembrar',
          'ja': '記憶に残したい時間',
          'ko': '기억하고 싶은 순간',
          'ar': 'لحظات تستحق التذكر',
        }),
        body: LocalizedCopy({
          'en':
              'Share conversations and memories with an AI companion who remembers your time together.',
          'zh': '与 AI 伴侣分享对话和回忆，让你们共度的时光被认真记住。',
          'zh_TW': '與 AI 伴侶分享對話和回憶，讓你們共度的時光被認真記住。',
          'es':
              'Comparte conversaciones y recuerdos con un compañero de IA que recuerda el tiempo que pasan juntos.',
          'pt':
              'Compartilhe conversas e memórias com um companheiro de IA que se lembra do tempo que passam juntos.',
          'ja': 'AIコンパニオンと会話や思い出を重ね、一緒に過ごした時間を大切に残しましょう。',
          'ko': 'AI 동반자와 대화와 추억을 나누고 함께한 시간을 기억하게 하세요.',
          'ar':
              'شارك الأحاديث والذكريات مع رفيق ذكاء اصطناعي يتذكر الوقت الذي قضيتماه معًا.',
        }),
      ),
    ],
  );
  WhatsNewCampaignContent? whatsNew;
  final socialLinks = const SocialMediaLinks().obs;
  final legalDocuments = <LegalDocumentType, LegalDocument>{}.obs;

  LegalDocument? legalDocument(LegalDocumentType type) => legalDocuments[type];

  bool get hasCurrentLegalDocuments =>
      legalDocument(LegalDocumentType.privacy)?.isUsable == true &&
      legalDocument(LegalDocumentType.terms)?.isUsable == true;

  Future<void> load() async {
    try {
      final raw = await ApiClient.instance.get('/v1/app-content');
      if (raw is! Map) return;
      final onboardingRaw = raw['onboarding'];
      final whatsNewRaw = raw['whats_new'];
      final socialLinksRaw = raw['social_links'];
      final legalDocumentsRaw = raw['legal_documents'];
      if (onboardingRaw is Map) {
        onboarding =
            OnboardingContent.from(Map<String, dynamic>.from(onboardingRaw));
      }
      if (whatsNewRaw is Map) {
        whatsNew = WhatsNewCampaignContent.from(
            Map<String, dynamic>.from(whatsNewRaw));
      }
      if (socialLinksRaw is Map) {
        socialLinks.value =
            SocialMediaLinks.from(Map<String, dynamic>.from(socialLinksRaw));
      }
      if (legalDocumentsRaw is Map) {
        final parsed = <LegalDocumentType, LegalDocument>{};
        for (final value in legalDocumentsRaw.values) {
          if (value is! Map) continue;
          final document = LegalDocument.from(Map<String, dynamic>.from(value));
          if (document.isUsable) parsed[document.type] = document;
        }
        legalDocuments.assignAll(parsed);
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
