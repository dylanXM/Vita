import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/app_content_controller.dart';
import '../../core/analytics_service.dart';
import '../auth/auth_controller.dart';
import '../billing/billing_controller.dart';
import '../billing/credits_page.dart';
import '../billing/subscription_page.dart';
import '../settings/settings_page.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Me tab — profile header, credits, subscription and settings.
class MePage extends StatelessWidget {
  const MePage({super.key});

  Future<void> _rateApp() async {
    AnalyticsService.to.track('profile_rate_clicked', category: 'profile');
    final url = defaultTargetPlatform == TargetPlatform.iOS
        ? appStoreUrl
        : playStoreUrl;
    if (url.isEmpty ||
        !await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication)) {
      Get.snackbar('me.rate'.tr, 'me.storeUnavailable'.tr);
    }
  }

  Future<void> _contactUs() async {
    AnalyticsService.to.track('profile_contact_clicked', category: 'profile');
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {'subject': 'Vita App Support'},
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      Get.snackbar('me.contact'.tr,
          'me.emailUnavailable'.trParams({'email': supportEmail}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final billing = BillingController.to;
    final vita = context.vita;
    final plan = billing.isSubscribed
        ? 'Vita ${billing.entitlements.join(' + ').toUpperCase()}'
        : 'me.free'.tr;
    final inviteCode = auth.profile.value?['invite_code'] as String? ?? '';

    return Scaffold(
      backgroundColor: vita.pageBg,
      // Bottom is open so the list scrolls behind the floating glass tab bar.
      body: SafeArea(
        bottom: false,
        child: Obx(
          () => ListView(
            padding: const EdgeInsets.only(bottom: 90),
            children: [
              const VitaTabHeader(title: 'Vita', showDivider: false),
              // Account summary follows the same tap-target and surface rhythm
              // as the grouped menu rows below.
              Container(
                color: vita.surface,
                padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/icons/profile_default.png',
                        width: 62,
                        height: 62,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.email.isEmpty ? 'me.account'.tr : auth.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: vita.text,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            plan,
                            style: TextStyle(
                              fontSize: 13,
                              color: vita.subText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Subscription group.
              VitaCard(
                radius: 0,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    VitaListTile(
                      customIcon: const VitaMenuIcon(
                        icon: Icons.workspace_premium_outlined,
                        color: Color(0xFFE9A820),
                      ),
                      title: 'me.plus.title'.tr,
                      subtitle: billing.isSubscribed
                          ? 'me.plus.active'.trParams({
                              'ent':
                                  billing.entitlements.join(', ').toUpperCase(),
                            })
                          : 'me.plus.unlock'.tr,
                      borderRadius: BorderRadius.zero,
                      onTap: () {
                        AnalyticsService.to.track('subscription_page_opened',
                            category: 'billing', properties: {'source': 'me'});
                        Get.to(() => const SubscriptionPage(),
                            transition: Transition.cupertino,
                            duration: const Duration(milliseconds: 300));
                      },
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      customIcon: const VitaMenuIcon(
                        icon: Icons.paid_outlined,
                        color: Color(0xFFF1A33B),
                      ),
                      title: 'me.credits'.tr,
                      subtitle: 'me.credits.available'.trParams({
                        'n': '${billing.balance.value}',
                      }),
                      borderRadius: BorderRadius.zero,
                      onTap: () {
                        AnalyticsService.to.track('credits_page_opened',
                            category: 'billing', properties: {'source': 'me'});
                        Get.to(() => const CreditsPage(),
                            transition: Transition.cupertino,
                            duration: const Duration(milliseconds: 300));
                      },
                    ),
                  ],
                ),
              ),

              // Settings.
              VitaCard(
                radius: 0,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    VitaListTile(
                      customIcon: const VitaMenuIcon(
                        icon: Icons.card_giftcard_outlined,
                        color: Color(0xFFE86C8D),
                      ),
                      title: 'me.inviteCode'.tr,
                      subtitle: inviteCode.isEmpty ? '—' : inviteCode,
                      borderRadius: BorderRadius.zero,
                      onTap: inviteCode.isEmpty
                          ? null
                          : () async {
                              AnalyticsService.to.track(
                                  'profile_invite_code_copied',
                                  category: 'profile');
                              await Clipboard.setData(
                                  ClipboardData(text: inviteCode));
                              Get.snackbar(
                                  'me.inviteCode'.tr, 'me.inviteCopied'.tr);
                            },
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      customIcon: const VitaMenuIcon(
                        icon: Icons.star_outline_rounded,
                        color: Color(0xFFE9A820),
                      ),
                      title: 'me.rate'.tr,
                      borderRadius: BorderRadius.zero,
                      onTap: _rateApp,
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      customIcon: const VitaMenuIcon(
                        icon: Icons.mail_outline_rounded,
                        color: Color(0xFF4A90E2),
                      ),
                      title: 'me.contact'.tr,
                      subtitle: supportEmail,
                      borderRadius: BorderRadius.zero,
                      onTap: _contactUs,
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      customIcon: const VitaMenuIcon(
                        icon: Icons.settings_outlined,
                        color: Color(0xFF7C8796),
                      ),
                      title: 'me.settings'.tr,
                      borderRadius: BorderRadius.zero,
                      onTap: () {
                        AnalyticsService.to.track('profile_settings_opened',
                            category: 'profile');
                        Get.to(() => const SettingsPage(),
                            transition: Transition.cupertino,
                            duration: const Duration(milliseconds: 300));
                      },
                    ),
                  ],
                ),
              ),

              Obx(() {
                final links = AppContentController.to.socialLinks.value;
                if (links.isEmpty) return const SizedBox.shrink();
                return _SocialMediaCard(links: links);
              }),

              const SizedBox(height: 24),
              Text(
                'me.version'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: vita.subText),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialMediaCard extends StatelessWidget {
  const _SocialMediaCard({required this.links});

  final SocialMediaLinks links;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final items = <({String name, String url, String icon})>[
      (
        name: 'Instagram',
        url: links.instagramUrl,
        icon: 'assets/icons/instagram.svg'
      ),
      (name: 'TikTok', url: links.tiktokUrl, icon: 'assets/icons/tiktok.svg'),
      (name: 'X', url: links.xUrl, icon: 'assets/icons/x.svg'),
      (
        name: 'Discord',
        url: links.discordUrl,
        icon: 'assets/icons/discord.svg'
      ),
    ].where((item) => item.url.isNotEmpty).toList();

    return VitaCard(
      radius: 0,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('me.social.title'.tr, style: vita.sectionTitle),
          const SizedBox(height: 4),
          Text('me.social.subtitle'.tr, style: vita.sub),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < items.length; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                Expanded(child: _SocialMediaButton(item: items[index])),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SocialMediaButton extends StatelessWidget {
  const _SocialMediaButton({required this.item});

  final ({String name, String url, String icon}) item;

  Future<void> _open() async {
    AnalyticsService.to.track(
      'profile_social_link_clicked',
      category: 'profile',
      properties: {'platform': item.name.toLowerCase()},
    );
    final uri = Uri.tryParse(item.url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      Get.snackbar('me.social.title'.tr, 'me.social.unavailable'.tr);
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      Get.snackbar('me.social.title'.tr, 'me.social.unavailable'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Semantics(
      button: true,
      label: item.name,
      child: Material(
        color: vita.greenTint,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  item.icon,
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(vita.text, BlendMode.srcIn),
                ),
                const SizedBox(height: 6),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: vita.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
