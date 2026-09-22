import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'billing_controller.dart';
import 'billing_products.dart';

/// WeChat-style wallet page: one quiet balance surface and continuous grouped
/// rows for purchases and transactions.
class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(leading: const VitaBackButton(), title: Text('credits.title'.tr)),
      body: Obx(() => RefreshIndicator(
            onRefresh: ctrl.refreshCredits,
            child: _body(context, ctrl),
          )),
    );
  }

  Widget _body(BuildContext context, BillingController ctrl) {
    final packs = _creditPacks(ctrl);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        Container(
          color: context.vita.surface,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: context.vita.greenTint,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.account_balance_wallet_outlined,
                    color: context.vita.green, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('credits.balance'.tr,
                        style: TextStyle(
                            fontSize: 13.5, color: context.vita.subText)),
                    const SizedBox(height: 2),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${ctrl.balance.value}',
                          style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: context.vita.text,
                              height: 1.15)),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text('credits.unit'.tr,
                            style: TextStyle(
                                fontSize: 13, color: context.vita.subText)),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        _SectionLabel('credits.buyMore'.tr),
        if (packs.isEmpty)
          const _PacksHint()
        else
          _GroupedSurface(
            children: [
              for (var i = 0; i < packs.length; i++) ...[
                _PackRow(package: packs[i]),
                if (i < packs.length - 1) const _Hairline(),
              ],
            ],
          ),
        _SectionLabel('credits.history'.tr),
        if (ctrl.transactions.isEmpty)
          Container(
            color: context.vita.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            child: Text('credits.empty'.tr,
                style: TextStyle(fontSize: 14, color: context.vita.subText)),
          )
        else
          _GroupedSurface(
            children: [
              for (var i = 0; i < ctrl.transactions.length; i++) ...[
                _TxRow(tx: ctrl.transactions[i]),
                if (i < ctrl.transactions.length - 1) const _Hairline(),
              ],
            ],
          ),
      ],
    );
  }

  List<Package> _creditPacks(BillingController ctrl) {
    final offerings = ctrl.offerings.value;
    if (offerings == null) return const [];
    final packs = <Package>[];
    final seen = <String>{};
    void collect(Offering? offering) {
      if (offering == null) return;
      for (final package in offering.availablePackages) {
        final id = package.storeProduct.identifier;
        if (isCoinProduct(package.identifier, id) && seen.add(id)) {
          packs.add(package);
        }
      }
    }

    collect(offerings.current);
    offerings.all.forEach((_, offering) => collect(offering));
    return packs;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Text(text,
          style: TextStyle(fontSize: 13, color: context.vita.subText)),
    );
  }
}

class _GroupedSurface extends StatelessWidget {
  const _GroupedSurface({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        color: context.vita.surface,
        child: Column(children: children),
      );
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Divider(
      height: 0.5, thickness: 0.5, indent: 68, color: context.vita.divider);
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.package});
  final Package package;

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    final store = package.storeProduct;
    final price =
        store.priceString.isEmpty ? 'credits.buy'.tr : store.priceString;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: context.vita.greenTint,
                borderRadius: BorderRadius.circular(6)),
            child:
                Icon(Icons.toll_outlined, size: 22, color: context.vita.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(store.title.isNotEmpty ? store.title : package.identifier,
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: context.vita.text)),
                if (store.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(store.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: context.vita.subText)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed:
                  ctrl.busy.value ? null : () => ctrl.purchasePackage(package),
              style: OutlinedButton.styleFrom(
                  foregroundColor: context.vita.green,
                  side: BorderSide(color: context.vita.green),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(64, 44)),
              child: Text(price,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PacksHint extends StatelessWidget {
  const _PacksHint();

  @override
  Widget build(BuildContext context) => Container(
        color: context.vita.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Text('credits.noPacks'.tr,
            style: TextStyle(
                fontSize: 13, color: context.vita.subText, height: 1.5)),
      );
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});
  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final description = tx['description'] as String? ?? '';
    final kind = tx['kind'] as String? ?? '';
    final createdAt = tx['created_at'] as String?;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(description.isEmpty ? kind : description,
                    style: TextStyle(fontSize: 15, color: context.vita.text)),
                if (createdAt != null) ...[
                  const SizedBox(height: 3),
                  Text(
                      formatDate(
                          DateTime.tryParse(createdAt) ?? DateTime.now()),
                      style:
                          TextStyle(fontSize: 12, color: context.vita.subText)),
                ],
              ],
            ),
          ),
          Text(amount >= 0 ? '+$amount' : '$amount',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: amount >= 0 ? context.vita.green : context.vita.text)),
        ]),
      ),
    );
  }
}
