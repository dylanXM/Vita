import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import 'billing_controller.dart';

/// Subscription page — Plus / Premium plan cards (RevenueCat) plus a restore
/// path. Value is expressed in product terms, not tokens (per the monetisation
/// plan). Tapping a card opens a detail bottom sheet.
class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('me.plus.title'.tr)),
      body: Obx(() => _buildBody(context, ctrl)),
    );
  }

  Widget _buildBody(BuildContext context, BillingController ctrl) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        // Active subscription banner.
        if (ctrl.isSubscribed)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: context.vita.greenTint,
              borderRadius: BorderRadius.zero,
            ),
            child: Row(
              children: [
                Icon(Icons.verified, color: context.vita.green, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'subscription.active'.tr,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.vita.text),
                  ),
                ),
              ],
            ),
          ),
        if (!ctrl.isSubscribed) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'subscription.hero'.tr,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.vita.text),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'subscription.description'.tr,
              style: TextStyle(
                  fontSize: 13, color: context.vita.subText, height: 1.5),
            ),
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
          ...ctrl.offerings.value!.current!.availablePackages.map(
            (p) => _PlanCard(
              package: p,
              onSubscribe: () => ctrl.purchasePackage(p),
              onDetails: () => _showPlanSheet(context, p),
            ),
          ),

        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: ctrl.busy.value ? null : ctrl.restorePurchases,
            icon: const Icon(Icons.settings_backup_restore, size: 18),
            label: Text('subscription.restore'.tr,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'subscription.legal'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5, color: context.vita.subText, height: 1.5),
        ),
      ],
    );
  }

  void _showPlanSheet(BuildContext context, Package package) {
    final ctrl = BillingController.to;
    final store = package.storeProduct;
    final title = store.title.isNotEmpty ? store.title : package.identifier;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.vita.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Text(title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.vita.text)),
              const SizedBox(height: 8),
              Text(
                store.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: context.vita.subText, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: ctrl.busy.value
                      ? null
                      : () {
                          Get.back();
                          ctrl.purchasePackage(package);
                        },
                  child: Text(
                    store.priceString.isEmpty
                        ? 'subscription.subscribe'.tr
                        : 'subscription.subscribePrice'
                            .trParams({'price': store.priceString}),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.package,
    required this.onSubscribe,
    required this.onDetails,
  });

  final Package package;
  final VoidCallback onSubscribe;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final store = package.storeProduct;
    final isPremium = package.identifier.toLowerCase().contains('premium');
    final title = store.title.isNotEmpty ? store.title : package.identifier;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDetails,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.vita.surface,
          borderRadius: BorderRadius.zero,
          border: Border.all(
              color: isPremium ? context.vita.green : context.vita.divider,
              width: isPremium ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.vita.text)),
                ),
                if (isPremium)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.vita.greenTint,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'subscription.recommended'.tr,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.vita.green),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              store.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, color: context.vita.subText, height: 1.5),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  store.priceString.isEmpty ? '—' : store.priceString,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: context.vita.text),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        isPremium ? context.vita.green : context.vita.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: isPremium
                        ? null
                        : Border.fromBorderSide(
                            BorderSide(color: context.vita.green)),
                  ),
                  child: Text(
                    'subscription.subscribe'.tr,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isPremium ? Colors.white : context.vita.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
        color: context.vita.surface,
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('subscription.notConfigured'.tr,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.vita.text)),
          SizedBox(height: 4),
          Text(
            'subscription.notConfiguredHint'.tr,
            style: TextStyle(fontSize: 12, color: context.vita.subText),
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
        color: context.vita.surface,
        borderRadius: BorderRadius.zero,
      ),
      child: Text(
        'subscription.noProducts'.trParams({
          'status': revenueCatApiKey.isEmpty
              ? 'subscription.keyEmpty'.tr
              : 'subscription.keySet'.tr
        }),
        style: TextStyle(fontSize: 12, color: context.vita.subText),
      ),
    );
  }
}
