import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
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
              const VitaTabHeader(title: 'Vita'),
              // Account summary follows the same tap-target and surface rhythm
              // as the grouped menu rows below.
              Container(
                color: vita.surface,
                padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
                child: Row(
                  children: [
                    VitaAvatar(
                      name: auth.email,
                      radius: 31,
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
                      icon: Icons.workspace_premium_outlined,
                      title: 'me.plus.title'.tr,
                      subtitle: billing.isSubscribed
                          ? 'me.plus.active'.trParams({
                              'ent':
                                  billing.entitlements.join(', ').toUpperCase(),
                            })
                          : 'me.plus.unlock'.tr,
                      borderRadius: BorderRadius.zero,
                      onTap: () => Get.to(
                        () => const SubscriptionPage(),
                        transition: Transition.cupertino,
                        duration: const Duration(milliseconds: 300),
                      ),
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      icon: Icons.toll_outlined,
                      title: 'me.credits'.tr,
                      subtitle: 'me.credits.available'.trParams({
                        'n': '${billing.balance.value}',
                      }),
                      borderRadius: BorderRadius.zero,
                      onTap: () => Get.to(
                        () => const CreditsPage(),
                        transition: Transition.cupertino,
                        duration: const Duration(milliseconds: 300),
                      ),
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
                      icon: Icons.card_giftcard_outlined,
                      title: 'me.inviteCode'.tr,
                      subtitle: inviteCode.isEmpty ? '—' : inviteCode,
                      borderRadius: BorderRadius.zero,
                      onTap: inviteCode.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                  ClipboardData(text: inviteCode));
                              Get.snackbar(
                                  'me.inviteCode'.tr, 'me.inviteCopied'.tr);
                            },
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      icon: Icons.star_outline,
                      title: 'me.rate'.tr,
                      borderRadius: BorderRadius.zero,
                      onTap: _rateApp,
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      icon: Icons.mail_outline,
                      title: 'me.contact'.tr,
                      subtitle: supportEmail,
                      borderRadius: BorderRadius.zero,
                      onTap: _contactUs,
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      icon: Icons.settings_outlined,
                      title: 'me.settings'.tr,
                      borderRadius: BorderRadius.zero,
                      onTap: () => Get.to(
                        () => const SettingsPage(),
                        transition: Transition.cupertino,
                        duration: const Duration(milliseconds: 300),
                      ),
                    ),
                  ],
                ),
              ),

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
