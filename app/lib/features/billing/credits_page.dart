import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'billing_controller.dart';

/// Credits page — balance, credit packs (RevenueCat consumables) and the
/// transaction history synced from the server via the RevenueCat webhook.
class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Credits')),
      body: Obx(() => _buildBody(ctrl)),
    );
  }

  Widget _buildBody(BillingController ctrl) {
    final packs = _creditPacks(ctrl);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Balance card.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: VitaColors.green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              const Text('Your balance', style: TextStyle(fontSize: 13, color: VitaColors.subText)),
              const SizedBox(height: 6),
              Obx(
                () => Text(
                  '${ctrl.balance.value}',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: VitaColors.text),
                ),
              ),
              const SizedBox(height: 2),
              const Text('credits', style: TextStyle(fontSize: 13, color: VitaColors.subText)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Credit packs.
        const Text('Buy more', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: VitaColors.text)),
        const SizedBox(height: 10),
        if (packs.isEmpty)
          const _PacksHint()
        else
          ...packs.map((p) => _PackRow(package: p)),
        const SizedBox(height: 20),

        // History.
        const Text('History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: VitaColors.text)),
        const SizedBox(height: 10),
        if (ctrl.transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No transactions yet', style: TextStyle(fontSize: 13, color: VitaColors.subText)),
          )
        else
          ...ctrl.transactions.map((t) => _TxRow(tx: t)),
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

class _PackRow extends StatelessWidget {
  const _PackRow({required this.package});

  final Package package;

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    final store = package.storeProduct;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: VitaColors.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              store.title.isNotEmpty ? store.title : package.identifier,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: VitaColors.text),
            ),
          ),
          ElevatedButton(
            onPressed: ctrl.busy.value ? null : () => ctrl.purchasePackage(package),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(88, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(store.priceString.isEmpty ? 'Buy' : store.priceString),
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
        color: VitaColors.pageBg,
        borderRadius: BorderRadius.circular(12),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: VitaColors.divider))),
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
              color: amount >= 0 ? VitaColors.green : VitaColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
