import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'billing_controller.dart';
import 'billing_products.dart';
import 'billing_sync_banner.dart';
import '../ads/admob_controller.dart';

/// Coin balance, experience purchases and recent activity.
class CreditsPage extends StatefulWidget {
  const CreditsPage({super.key, this.purchaseOnly = false});

  final bool purchaseOnly;

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> {
  @override
  void initState() {
    super.initState();
    if (widget.purchaseOnly) {
      BillingController.to.refreshCredits();
    } else {
      AdmobController.to.refreshConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = BillingController.to;
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
          leading: const VitaBackButton(),
          title: Text(
              (widget.purchaseOnly ? 'credits.purchaseTitle' : 'credits.title')
                  .tr)),
      body: Obx(() => RefreshIndicator(
            onRefresh: () async {
              await ctrl.refreshCredits();
              if (!widget.purchaseOnly)
                await AdmobController.to.refreshConfig();
            },
            child: _body(context, ctrl),
          )),
    );
  }

  Widget _body(BuildContext context, BillingController ctrl) {
    final packs = _creditPacks(ctrl);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.vita.greenTint, context.vita.surface]),
            border:
                Border.all(color: context.vita.green.withValues(alpha: .18)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: context.vita.greenTint,
                    borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.auto_awesome_rounded,
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
                              fontSize: 44,
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
        const BillingSyncBanner(),
        if (!widget.purchaseOnly) ...[
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: AdmobBanner(),
          ),
          Obx(() {
            final ads = AdmobController.to;
            if (!ads.canShowRewarded) return const SizedBox.shrink();
            final reward =
                (ads.config.value?['reward_credits'] as num?)?.toInt() ?? 0;
            final remaining =
                (ads.config.value?['remaining_today'] as num?)?.toInt() ?? 0;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: ads.loadingReward.value ? null : ads.showRewarded,
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text('ads.watchReward'.trParams({
                    'credits': '$reward',
                    'remaining': '$remaining',
                  })),
                ),
              ),
            );
          }),
        ],
        _SectionLabel('credits.buyMore'.tr),
        if (packs.isEmpty)
          const _PacksHint()
        else
          Column(
            children: [
              for (final package in packs)
                Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PackRow(package: package)),
            ],
          ),
        if (!widget.purchaseOnly) ...[
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
    packs.sort((a, b) {
      final aCoins = vitaCoinProductIds[a.storeProduct.identifier.toLowerCase()]!;
      final bCoins = vitaCoinProductIds[b.storeProduct.identifier.toLowerCase()]!;
      return aCoins.compareTo(bCoins);
    });
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
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: context.vita.text)),
    );
  }
}

class _GroupedSurface extends StatelessWidget {
  const _GroupedSurface({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: context.vita.surface,
            borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
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
    final coins = vitaCoinProductIds[store.identifier.toLowerCase()]!;
    final quantity = MaterialLocalizations.of(context).formatDecimal(coins);
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.vita.green.withValues(alpha: .14)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.vita.greenTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.toll_rounded, size: 25, color: context.vita.green),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(quantity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 25,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: context.vita.text))),
              const SizedBox(height: 4),
              Flexible(child: Text('credits.unit'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.vita.subText))),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          height: 44,
          child: FilledButton(
            onPressed:
                ctrl.busy.value ? null : () => ctrl.purchasePackage(package),
            style: FilledButton.styleFrom(
              backgroundColor: context.vita.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(price,
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _PacksHint extends StatelessWidget {
  const _PacksHint();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: context.vita.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.vita.divider)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
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
    const names = {
      'ai_pet_feed': 'credits.petFeed',
      'story_chapter': 'credits.storyChapter',
      'story_storyboard': 'credits.storyboard',
      'outfit_casual': 'experience.outfit.casual',
      'outfit_evening': 'experience.outfit.evening',
      'outfit_travel': 'experience.outfit.travel',
      'date_coffee': 'experience.date.coffee',
      'date_movie': 'experience.date.movie',
      'date_dinner': 'experience.date.dinner',
      'gift_coffee': 'experience.gift.coffee',
      'gift_flowers': 'experience.gift.flowers',
      'gift_cake': 'experience.gift.cake',
      'gift_keepsake': 'experience.gift.keepsake',
      'life_photo': 'experience.photo',
      'voice_reply': 'experience.voice',
      'memory_card': 'experience.keepsake',
    };
    final productKey =
        description.contains(':') ? description.split(':').last : '';
    final translatedName = names[productKey]?.tr;
    final productName =
        translatedName != null && description.startsWith('refund:')
            ? 'credits.refundLabel'.trParams({'name': translatedName})
            : translatedName;
    final displayDescription = tx['kind'] == 'ad_reward'
        ? 'ads.rewardHistory'.tr
        : description.startsWith('companion-transfer:')
            ? 'chat.transfer'.tr
            : productName ??
                (description.startsWith('product:') ||
                        description.startsWith('refund:')
                    ? 'experience.title'.tr
                    : description);
    final kind = tx['kind'] as String? ?? '';
    final createdAt = tx['created_at'] as String?;
    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(height: 80),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: context.vita.greenTint,
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(
                  amount >= 0
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  size: 18,
                  color: context.vita.green)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(displayDescription.isEmpty ? kind : displayDescription,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
