import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'billing_controller.dart';

/// Credits page — gradient balance card, credit packs and the transaction
/// history synced from the server via the RevenueCat webhook.
class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(title: Text('credits.title'.tr)),
      body: Obx(() => _buildBody(context, ctrl)),
    );
  }

  Widget _buildBody(BuildContext context, BillingController ctrl) {
    final packs = _creditPacks(ctrl);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      children: [
        // Balance card.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: context.vita.surface,
          ),
          child: Column(
            children: [
              Text('credits.balance'.tr,
                  style: TextStyle(
                      fontSize: 13, color: context.vita.subText, height: 1.3)),
              const SizedBox(height: 4),
              Obx(
                () => Text(
                  '${ctrl.balance.value}',
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: context.vita.text,
                      height: 1.15),
                ),
              ),
              Text('credits.unit'.tr,
                  style: TextStyle(
                      fontSize: 13, color: context.vita.subText, height: 1.3)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Credit packs.
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child:
                Text('credits.buyMore'.tr, style: context.vita.sectionTitle)),
        const SizedBox(height: 12),
        if (packs.isEmpty)
          const _PacksHint()
        else
          ...packs.map((p) => _PackCard(package: p)),
        const SizedBox(height: 24),

        // History.
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child:
                Text('credits.history'.tr, style: context.vita.sectionTitle)),
        const SizedBox(height: 12),
        if (ctrl.transactions.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Text('credits.empty'.tr,
                style: TextStyle(fontSize: 13, color: context.vita.subText)),
          )
        else
          VitaCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < ctrl.transactions.length; i++) ...[
                  _TxRow(tx: ctrl.transactions[i]),
                  if (i != ctrl.transactions.length - 1)
                    const Divider(height: 0.5),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Credit packs are RevenueCat packages whose identifier starts with
  /// credits_ / coins_ (they map to the server-side grant on purchase).
  List<Package> _creditPacks(BillingController ctrl) {
    final o = ctrl.offerings.value;
    if (o == null) return const [];
    final packs = <Package>[];
    void collect(Offering? offering) {
      if (offering == null) return;
      for (final p in offering.availablePackages) {
        final id = p.identifier.toLowerCase();
        if (id.startsWith('credits_') || id.startsWith('coins_')) {
          packs.add(p);
        }
      }
    }

    collect(o.current);
    o.all.forEach((_, offering) => collect(offering));
    return packs;
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.package});

  final Package package;

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    final store = package.storeProduct;
    final price =
        store.priceString.isEmpty ? 'credits.buy'.tr : store.priceString;
    return VitaCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.title.isNotEmpty ? store.title : package.identifier,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.vita.text),
                ),
                if (store.description.isNotEmpty)
                  Text(
                    store.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.vita.subText),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: ctrl.busy.value ? null : () => ctrl.purchasePackage(package),
            child: Opacity(
              opacity: ctrl.busy.value ? 0.5 : 1,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: context.vita.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  price,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PacksHint extends StatelessWidget {
  const _PacksHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.vita.surface,
        borderRadius: BorderRadius.zero,
      ),
      child: Text(
        'credits.noPacks'.tr,
        style:
            TextStyle(fontSize: 12, color: context.vita.subText, height: 1.5),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});

  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final desc = tx['description'] as String? ?? '';
    final kind = tx['kind'] as String? ?? '';
    final when = tx['created_at'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc.isEmpty ? kind : desc,
                  style: TextStyle(fontSize: 14, color: context.vita.text),
                ),
                if (when != null)
                  Text(
                    formatDate(DateTime.tryParse(when) ?? DateTime.now()),
                    style: TextStyle(fontSize: 12, color: context.vita.subText),
                  ),
              ],
            ),
          ),
          Text(
            amount >= 0 ? '+$amount' : '$amount',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: amount >= 0 ? context.vita.green : context.vita.red,
            ),
          ),
        ],
      ),
    );
  }
}
