import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/notice.dart';
import '../../core/constants.dart';
import '../../core/app_content_controller.dart';
import '../../core/analytics_service.dart';
import '../auth/auth_controller.dart';
import '../billing/billing_controller.dart';
import '../billing/credits_page.dart';
import '../billing/subscription_page.dart';
import '../settings/settings_page.dart';
import '../settings/profile_edit_page.dart';
import '../settings/change_password_page.dart';
import 'invitation_page.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
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
      VitaNotice.error('me.rate'.tr, 'me.storeUnavailable'.tr);
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
      VitaNotice.error('me.contact'.tr,
          'me.emailUnavailable'.trParams({'email': supportEmail}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final billing = BillingController.to;
    final vita = context.vita;
    return Scaffold(
      backgroundColor: vita.pageBg,
      // Settings is the final action; the version follows it as metadata.
      body: SafeArea(
        bottom: false,
        child: Obx(
          () {
            return ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                const VitaTabHeader(title: 'Vita', showDivider: false),
                _LifePassport(
                  name: auth.nickname.isNotEmpty
                      ? auth.nickname
                      : (auth.email.isEmpty ? 'me.account'.tr : auth.email),
                  avatarUrl: auth.avatarUrl,
                  email: auth.email,
                ),
                _MeSectionTitle(title: 'me.membershipWallet'.tr),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: vita.green.withValues(alpha: .3)),
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [vita.greenTint, vita.surface]),
                  ),
                  child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(children: [
                          Expanded(
                              child: Text('Vita Plus & Premium',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: vita.green,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700))),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: vita.surface,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                      billing.isSubscribed
                                          ? 'me.membershipActive'.tr
                                          : 'me.free'.tr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: vita.green,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)))),
                        ])),
                    _MeAction(
                      icon: Icons.workspace_premium_rounded,
                      title: 'me.subscriptionLabel'.tr,
                      emphasized: true,
                      value: billing.isSubscribed
                          ? 'me.plus.active'.trParams({
                              'ent':
                                  billing.entitlements.join(', ').toUpperCase()
                            })
                          : 'me.plus.unlock'.tr,
                      onTap: () {
                        AnalyticsService.to.track('subscription_page_opened',
                            category: 'billing', properties: {'source': 'me'});
                        Get.to(() => const SubscriptionPage(),
                            transition: Transition.cupertino);
                      },
                    ),
                    const Divider(indent: 52, height: 0.5),
                    _MeAction(
                      icon: Icons.paid_rounded,
                      title: 'me.credits'.tr,
                      value: '${billing.balance.value}',
                      onTap: () {
                        AnalyticsService.to.track('credits_page_opened',
                            category: 'billing', properties: {'source': 'me'});
                        Get.to(() => const CreditsPage(),
                            transition: Transition.cupertino);
                      },
                    ),
                  ]),
                ),
                _MeSectionTitle(title: 'me.invitationSection'.tr),
                VitaCard(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _MeAction(
                    icon: Icons.confirmation_number_outlined,
                    title: 'invitation.title'.tr,
                    onTap: () => Get.to(() => const InvitationPage(),
                        transition: Transition.cupertino),
                  ),
                ),
                _MeSectionTitle(title: 'me.services'.tr),
                VitaCard(
                  radius: 12,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    _MeAction(
                        icon: Icons.mail_outline_rounded,
                        title: 'me.contact'.tr,
                        onTap: _contactUs),
                    const Divider(indent: 52, height: 0.5),
                    _MeAction(
                        icon: Icons.star_outline_rounded,
                        title: 'me.rate'.tr,
                        onTap: _rateApp),
                  ]),
                ),
                Obx(() {
                  final links = AppContentController.to.socialLinks.value;
                  if (links.isEmpty) return const SizedBox.shrink();
                  return _SocialMediaCard(links: links);
                }),
                _MeSectionTitle(title: 'me.accountSection'.tr),
                VitaCard(
                  radius: 12,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    _MeAction(
                      icon: Icons.lock_outline_rounded,
                      title: 'password.title'.tr,
                      onTap: () => Get.to(() => const ChangePasswordPage(),
                          transition: Transition.cupertino),
                    ),
                    const Divider(indent: 52, height: .5),
                    _MeAction(
                      icon: Icons.settings_outlined,
                      title: 'me.settings'.tr,
                      onTap: () {
                        AnalyticsService.to.track('profile_settings_opened',
                            category: 'profile');
                        Get.to(() => const SettingsPage(),
                            transition: Transition.cupertino,
                            duration: const Duration(milliseconds: 300));
                      },
                    ),
                  ]),
                ),
                Text(
                  'me.version'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: vita.subText),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MeSectionTitle extends StatelessWidget {
  const _MeSectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Text(title,
            style: TextStyle(
                color: context.vita.subText,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );
}

class _LifePassport extends StatelessWidget {
  const _LifePassport({
    required this.name,
    required this.avatarUrl,
    required this.email,
  });

  final String name;
  final String avatarUrl;
  final String email;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    return Container(
      height: 100,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: vita.divider),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [vita.greenTint, vita.surface, vita.surface],
          stops: const [0, .48, 1],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(children: [
          Positioned(
            top: -46,
            right: -34,
            child: Container(
              width: 142,
              height: 142,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: vita.green.withValues(alpha: .14), width: 1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 65,
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: avatarUrl.isEmpty
                          ? Image.asset('assets/icons/profile_default.png',
                              width: 62, height: 62, fit: BoxFit.cover)
                          : SizedBox(
                              width: 62,
                              height: 62,
                              child: VitaMediaImage(
                                url: avatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Image.asset(
                                  'assets/icons/profile_default.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: vita.text,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: vita.subText, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: vita.subText),
                  ]),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Get.to(() => const ProfileEditPage(),
                    transition: Transition.cupertino),
                child: Semantics(
                    button: true,
                    label: 'settings.profile'.tr,
                    child: const SizedBox.expand()),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _MeAction extends StatelessWidget {
  const _MeAction(
      {required this.icon,
      required this.title,
      this.value,
      this.emphasized = false,
      required this.onTap});

  final IconData icon;
  final String title;
  final String? value;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(icon, size: 20, color: context.vita.green),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: emphasized
                              ? context.vita.green
                              : context.vita.text,
                          fontSize: 15,
                          fontWeight:
                              emphasized ? FontWeight.w700 : FontWeight.w400))),
              if (value != null) ...[
                const SizedBox(width: 8),
                Expanded(
                    child: Text(value!,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: emphasized
                                ? context.vita.green
                                : context.vita.subText,
                            fontSize: 12,
                            fontWeight: emphasized
                                ? FontWeight.w600
                                : FontWeight.w400))),
              ],
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: context.vita.subText),
            ]),
          ),
        ),
      );
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
      radius: 20,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
      VitaNotice.error('me.social.title'.tr, 'me.social.unavailable'.tr);
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      VitaNotice.error('me.social.title'.tr, 'me.social.unavailable'.tr);
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
