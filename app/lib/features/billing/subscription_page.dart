import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import 'billing_controller.dart';

/// Subscription page — Plus / Premium plans (RevenueCat) plus a restore path.
/// Value is expressed in product terms, not tokens (per the monetisation plan).
class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Vita Plus & Premium')),
      body: Obx(() => _buildBody(ctrl)),
    );
  }

  Widget _buildBody(BillingController ctrl) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Active subscription banner.
        if (ctrl.isSubscribed)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VitaColors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified, color: VitaColors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You are on ${ctrl.entitlements.join(', ').toUpperCase()}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: VitaColors.text),
                  ),
                ),
              ],
            ),
          ),
        if (!ctrl.isSubscribed) ...[
          const Text(
            'More life, more memories, more of her.',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: VitaColors.text),
          ),
          const SizedBox(height: 6),
          const Text(
            'Subscription includes monthly credits for premium images, voice and more.',
            style: TextStyle(fontSize: 13, color: VitaColors.subText),
          ),
        ],
        const SizedBox(height: 20),

        // Plans from RevenueCat.
        if (!ctrl.rcReady.value)
          const _NotConfiguredCard()
        else if (ctrl.offerings.value == null ||
            (ctrl.offerings.value!.current?.availablePackages.isEmpty ?? true))
          const _NoOfferingsCard()
        else
          ...ctrl.offerings.value!.current!.availablePackages.map((p) => _PlanCard(package: p)),

        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: ctrl.busy.value ? null : ctrl.restorePurchases,
          icon: const Icon(Icons.settings_backup_restore, size: 18),
          label: const Text('Restore purchases'),
          style: TextButton.styleFrom(foregroundColor: VitaColors.green),
        ),
        const SizedBox(height: 24),
        const Text(
          'Subscriptions are billed through the App Store / Google Play and can be '
          'managed there. Credits included with a subscription are granted each '
          'billing period.',
          style: TextStyle(fontSize: 12, color: VitaColors.subText, height: 1.5),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.package});

  final Package package;

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    final store = package.storeProduct;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VitaColors.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.title.isNotEmpty ? store.title : package.identifier,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: VitaColors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  store.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: VitaColors.subText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: ctrl.busy.value ? null : () => ctrl.purchasePackage(package),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(88, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(store.priceString.isEmpty ? 'Subscribe' : store.priceString),
          ),
        ],
      ),
    );
  }
}

class _NotConfiguredCard extends StatelessWidget {
  const _NotConfiguredCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VitaColors.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RevenueCat not configured', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: VitaColors.text)),
          SizedBox(height: 4),
          Text(
            'Build with --dart-define=VITA_REVENUECAT_KEY=... to enable in-app purchases.',
            style: TextStyle(fontSize: 12, color: VitaColors.subText),
          ),
        ],
      ),
    );
  }
}

class _NoOfferingsCard extends StatelessWidget {
  const _NoOfferingsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VitaColors.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'No products configured in RevenueCat yet (api key: ${revenueCatApiKey.isEmpty ? 'empty' : 'set'}).',
        style: const TextStyle(fontSize: 12, color: VitaColors.subText),
      ),
    );
  }
}
