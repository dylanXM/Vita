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
      backgroundColor: VitaColors.pageBg,
      appBar: AppBar(title: const Text('Credits')),
      body: Obx(() => _buildBody(ctrl)),
    );
  }

  Widget _buildBody(BillingController ctrl) {
    final packs = _creditPacks(ctrl);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // Balance card.
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: VitaColors.brandGradient,
            borderRadius: BorderRadius.circular(VitaRadius.lg),
            boxShadow: [BoxShadow(color: VitaColors.green.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(
            children: [
              const Text('Your balance', style: TextStyle(fontSize: 13, color: Colors.white, height: 1.3)),
              const SizedBox(height: 4),
              Obx(
                () => Text(
                  '${ctrl.balance.value}',
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15),
                ),
              ),
              const Text('credits', style: TextStyle(fontSize: 13, color: Colors.white, height: 1.3)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Credit packs.
        const Text('Buy more', style: VitaText.sectionTitle),
        const SizedBox(height: 12),
        if (packs.isEmpty)
          const _PacksHint()
        else
          ...packs.map((p) => _PackCard(package: p)),
        const SizedBox(height: 24),

        // History.
        const Text('History', style: VitaText.sectionTitle),
        const SizedBox(height: 12),
        if (ctrl.transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No transactions yet', style: TextStyle(fontSize: 13, color: VitaColors.subText)),
          )
        else
          VitaCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < ctrl.transactions.length; i++) ...[
                  _TxRow(tx: ctrl.transactions[i]),
                  if (i != ctrl.transactions.length - 1) const Divider(height: 0.5),
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
    final price = store.priceString.isEmpty ? 'Buy' : store.priceString;
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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: VitaColors.text),
                ),
                if (store.description.isNotEmpty)
                  Text(
                    store.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: VitaColors.subText),
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: VitaColors.green,
                  borderRadius: BorderRadius.circular(VitaRadius.pill),
                ),
                child: Text(
                  price,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
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
        color: VitaColors.surface,
        borderRadius: BorderRadius.circular(VitaRadius.md),
        boxShadow: VitaShadow.card,
      ),
      child: const Text(
        'Create consumable products named credits_500 / credits_1000 / credits_5000 in '
        'RevenueCat and they will appear here automatically.',
        style: TextStyle(fontSize: 12, color: VitaColors.subText, height: 1.5),
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
                  style: const TextStyle(fontSize: 14, color: VitaColors.text),
                ),
                if (when != null)
                  Text(
                    formatDate(DateTime.tryParse(when) ?? DateTime.now()),
                    style: const TextStyle(fontSize: 12, color: VitaColors.subText),
                  ),
              ],
            ),
          ),
          Text(
            amount >= 0 ? '+$amount' : '$amount',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: amount >= 0 ? VitaColors.green : VitaColors.red,
            ),
          ),
        ],
      ),
    );
  }
}
