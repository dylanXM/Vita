import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../auth/auth_controller.dart';
import '../billing/billing_controller.dart';
import '../billing/credits_page.dart';
import '../billing/subscription_page.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

/// Me tab — profile header, credits, subscription and sign out.
class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final billing = BillingController.to;
    final plan = billing.isSubscribed ? 'Vita ${billing.entitlements.join(' + ').toUpperCase()}' : 'Free plan';

    return Scaffold(
      backgroundColor: VitaColors.pageBg,
      body: SafeArea(
        child: Obx(
          () => ListView(
            children: [
              // Gradient profile header.
              Container(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                decoration: const BoxDecoration(gradient: VitaColors.brandGradient),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: VitaAvatar(
                        name: auth.email,
                        radius: 30,
                        background: Colors.white,
                        textColor: VitaColors.green,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.email.isEmpty ? 'Account' : auth.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(VitaRadius.pill),
                            ),
                            child: Text(
                              plan,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Settings group.
              VitaCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    VitaListTile(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Vita Plus & Premium',
                      subtitle: billing.isSubscribed
                          ? 'Active · ${billing.entitlements.join(', ').toUpperCase()}'
                          : 'Unlock more of her life',
                      onTap: () => Get.to(
                        () => const SubscriptionPage(),
                        transition: Transition.cupertino,
                        duration: const Duration(milliseconds: 300),
                      ),
                    ),
                    const Divider(indent: 52, height: 0.5),
                    VitaListTile(
                      icon: Icons.toll_outlined,
                      title: 'Credits',
                      subtitle: '${billing.balance.value} available',
                      onTap: () => Get.to(
                        () => const CreditsPage(),
                        transition: Transition.cupertino,
                        duration: const Duration(milliseconds: 300),
                      ),
                    ),
                  ],
                ),
              ),

              // Sign out.
              Material(
                color: VitaColors.surface,
                child: InkWell(
                  onTap: () => _confirmSignOut(context, auth),
                  borderRadius: BorderRadius.circular(VitaRadius.md),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: VitaColors.surface,
                      borderRadius: BorderRadius.circular(VitaRadius.md),
                      boxShadow: VitaShadow.card,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: VitaColors.red.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.logout, size: 19, color: VitaColors.red),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Sign out',
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: VitaColors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Vita v1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: VitaColors.subText),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, AuthController auth) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: VitaColors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout, size: 26, color: VitaColors.red),
              ),
              const SizedBox(height: 14),
              const Text(
                'Sign out?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: VitaColors.text),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your companion will be waiting when you come back.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: VitaColors.subText),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: VitaColors.red),
                  onPressed: () {
                    Get.back();
                    auth.logout();
                  },
                  child: const Text('Sign out'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('Cancel', style: TextStyle(color: VitaColors.subText)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
