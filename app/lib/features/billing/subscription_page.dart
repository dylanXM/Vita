import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import 'billing_controller.dart';
import 'billing_products.dart';

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('me.plus.title'.tr)),
      body: Obx(() => _body(context, ctrl)),
    );
  }

  Widget _body(BuildContext context, BillingController ctrl) {
    final plans = ctrl.offerings.value?.current?.availablePackages
            .where((item) => isSubscriptionProduct(
                item.identifier, item.storeProduct.identifier))
            .toList() ??
        const <Package>[];
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _SubscriptionHero(active: ctrl.isSubscribed),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('subscription.choosePlan'.tr,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.vita.text)),
        ),
        const SizedBox(height: 10),
        if (!ctrl.rcReady.value)
          const _NotConfiguredCard()
        else if (plans.isEmpty)
          const _NoOfferingsCard()
        else
          ...plans.map((item) => _PlanCard(
                package: item,
                busy: ctrl.busy.value,
                onSubscribe: () => ctrl.purchasePackage(item),
                onDetails: () => _showPlanSheet(context, item),
              )),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: ctrl.busy.value ? null : ctrl.restorePurchases,
            icon: const Icon(Icons.settings_backup_restore, size: 18),
            label: Text('subscription.restore'.tr,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
          child: Text('subscription.legal'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5, color: context.vita.subText, height: 1.5)),
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
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: context.vita.greenTint, shape: BoxShape.circle),
                child: Icon(Icons.favorite_rounded,
                    color: context.vita.green, size: 28),
              ),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: context.vita.text)),
              if (store.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(store.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: context.vita.subText,
                        height: 1.5)),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: ctrl.busy.value
                      ? null
                      : () {
                          Get.back();
                          ctrl.purchasePackage(package);
                        },
                  child: Text(store.priceString.isEmpty
                      ? 'subscription.subscribe'.tr
                      : 'subscription.subscribePrice'
                          .trParams({'price': store.priceString})),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionHero extends StatelessWidget {
  const _SubscriptionHero({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.vita.surface,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: context.vita.greenTint, shape: BoxShape.circle),
            child: Icon(
                active ? Icons.verified_rounded : Icons.favorite_rounded,
                color: context.vita.green,
                size: 34),
          ),
          const SizedBox(height: 14),
          Text(active ? 'subscription.active'.tr : 'subscription.hero'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.vita.text,
                  height: 1.25)),
          const SizedBox(height: 8),
          Text('subscription.description'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: context.vita.subText, height: 1.5)),
          const SizedBox(height: 20),
          Row(children: const [
            _Benefit(
                icon: Icons.all_inclusive,
                labelKey: 'subscription.benefit.life'),
            _Benefit(
                icon: Icons.toll_outlined,
                labelKey: 'subscription.benefit.coins'),
            _Benefit(
                icon: Icons.auto_awesome_outlined,
                labelKey: 'subscription.benefit.experiences'),
          ]),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.labelKey});
  final IconData icon;
  final String labelKey;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: context.vita.green, size: 22),
          const SizedBox(height: 7),
          Text(labelKey.tr,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                  fontSize: 12.5, color: context.vita.text, height: 1.25)),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.package,
    required this.busy,
    required this.onSubscribe,
    required this.onDetails,
  });
  final Package package;
  final bool busy;
  final VoidCallback onSubscribe;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final store = package.storeProduct;
    final premium = isPremiumProduct(package.identifier, store.identifier);
    final title = store.title.isNotEmpty ? store.title : package.identifier;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: premium ? context.vita.green : context.vita.divider,
            width: premium ? 1.5 : 0.5),
      ),
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: context.vita.text)),
                ),
                if (premium)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: context.vita.greenTint,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('subscription.recommended'.tr,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.vita.green)),
                  ),
              ]),
              if (store.description.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(store.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: context.vita.subText,
                        height: 1.4)),
              ],
              const SizedBox(height: 15),
              Row(children: [
                Expanded(
                  child: Text(
                      store.priceString.isEmpty ? '—' : store.priceString,
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: context.vita.text)),
                ),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: busy ? null : onSubscribe,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.vita.green,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text('subscription.subscribe'.tr),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotConfiguredCard extends StatelessWidget {
  const _NotConfiguredCard();
  @override
  Widget build(BuildContext context) => _StateCard(
      title: 'subscription.notConfigured'.tr,
      message: 'subscription.notConfiguredHint'.tr);
}

class _NoOfferingsCard extends StatelessWidget {
  const _NoOfferingsCard();
  @override
  Widget build(BuildContext context) => _StateCard(
        title: 'subscription.noProducts'.trParams({
          'status': revenueCatApiKey.isEmpty
              ? 'subscription.keyEmpty'.tr
              : 'subscription.keySet'.tr
        }),
      );
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.title, this.message});
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      color: context.vita.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.vita.text)),
        if (message != null) ...[
          const SizedBox(height: 5),
          Text(message!,
              style: TextStyle(
                  fontSize: 12.5, color: context.vita.subText, height: 1.4)),
        ],
      ]),
    );
  }
}
