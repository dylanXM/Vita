import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../billing/billing_controller.dart';
import '../billing/credits_page.dart';
import '../billing/subscription_page.dart';

/// Me tab — account, credits, subscription and settings, settings-list style.
class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final billing = BillingController.to;
    return Scaffold(
      backgroundColor: VitaColors.pageBg,
      body: SafeArea(
        child: Obx(
          () => ListView(
            children: [
              // Profile header.
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    VitaAvatar(name: auth.email, radius: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.email.isEmpty ? 'Account' : auth.email,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: VitaColors.text),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            billing.isSubscribed ? 'Vita ${billing.entitlements.join(' + ').toUpperCase()}' : 'Free plan',
                            style: const TextStyle(fontSize: 13, color: VitaColors.subText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Settings group.
              Container(
                color: Colors.white,
                child: Column(
                  children: [
                    VitaListTile(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Vita Plus & Premium',
                      subtitle: billing.isSubscribed
                          ? 'Active · ${billing.entitlements.join(', ').toUpperCase()}'
                          : 'Unlock more of her life',
                      onTap: () => Get.to(() => const SubscriptionPage()),
                    ),
                    const Divider(indent: 52),
                    VitaListTile(
                      icon: Icons.toll_outlined,
                      title: 'Credits',
                      subtitle: '${billing.balance.value} available',
                      onTap: () => Get.to(() => const CreditsPage()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Sign out.
              Container(
                color: Colors.white,
                child: ListTile(
                  title: const Text(
                    'Sign out',
                    style: TextStyle(color: Color(0xFFE64340), fontSize: 16),
                  ),
                  onTap: () => Get.defaultDialog(
                    title: 'Sign out?',
                    middleText: 'Your companion will be waiting when you come back.',
                    textConfirm: 'Sign out',
                    confirmTextColor: Colors.white,
                    onConfirm: () {
                      Get.back();
                      auth.logout();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Vita v1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: VitaColors.subText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
