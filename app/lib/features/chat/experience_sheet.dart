import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/analytics_service.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../billing/billing_controller.dart';

class ExperienceSheet extends StatefulWidget {
  const ExperienceSheet(
      {super.key,
      required this.companionId,
      required this.onCompleted,
      this.onResult});

  final String companionId;
  final Future<void> Function() onCompleted;
  final Future<void> Function(Map<String, dynamic> response)? onResult;

  @override
  State<ExperienceSheet> createState() => _ExperienceSheetState();
}

class _ExperienceSheetState extends State<ExperienceSheet> {
  bool _loading = true;
  String? _buying;
  int _balance = 0;
  List<Map<String, dynamic>> _products = const [];
  Map<String, bool> _owned = const {};
  String _equipped = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance
          .get('/v1/companions/${widget.companionId}/experiences');
      if (!mounted || data is! Map) return;
      setState(() {
        _balance = data['balance'] as int? ?? 0;
        _products = (data['products'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _owned = (data['owned_outfits'] as Map? ?? const {})
            .map((key, value) => MapEntry('$key', value == true));
        _equipped = data['equipped_outfit'] as String? ?? '';
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (error.action == 'open_subscription') {
        Navigator.of(context).pop();
        Get.toNamed('/subscription');
      } else {
        Get.snackbar('experience.failed'.tr, error.message);
      }
    }
  }

  Future<void> _purchase(Map<String, dynamic> product) async {
    final key = product['key'] as String? ?? '';
    final coins = product['coins'] as int? ?? 0;
    final owned = _owned[key] == true;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text((product['name_key'] as String? ?? key).tr),
        content: Text(owned
            ? 'experience.equipConfirm'.tr
            : 'experience.confirm'.trParams({'coins': '$coins'})),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              
              child: Text('common.cancel'.tr, style: const TextStyle(color: CupertinoColors.systemGrey))),
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(owned ? 'experience.equip'.tr : 'experience.use'.tr)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _buying = key);
    try {
      final data = await ApiClient.instance.post(
        '/v1/companions/${widget.companionId}/experiences/$key',
        data: {
          'idempotency_key':
              '${widget.companionId}-$key-${DateTime.now().microsecondsSinceEpoch}',
          'input': <String, dynamic>{}
        },
      );
      if (data is Map && data['balance'] is int) {
        _balance = data['balance'] as int;
      }
      await BillingController.to.refreshCredits();
      if (data is Map && widget.onResult != null) {
        await widget.onResult!(Map<String, dynamic>.from(data));
      } else {
        await widget.onCompleted();
      }
      AnalyticsService.to
          .track('experience_purchased', category: 'billing', properties: {
        'companion_id': widget.companionId,
        'product_key': key,
        'coins': owned ? 0 : coins,
      });
      if (!mounted) return;
      Get.snackbar('experience.done'.tr,
          owned ? 'experience.equipped'.tr : 'experience.doneMessage'.tr);
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.action == 'open_credits' ||
          error.code == 'insufficient_credits') {
        Navigator.of(context).pop();
        Get.toNamed('/credits');
      } else if (error.action == 'open_subscription') {
        Navigator.of(context).pop();
        Get.toNamed('/subscription');
      } else {
        Get.snackbar('experience.failed'.tr, error.message);
      }
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(children: [
          // Header — centered title, matching the app nav-bar style.
          SizedBox(
            height: 52,
            child: Center(
              child: Text('experience.title'.tr,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.vita.text)),
            ),
          ),
          Divider(height: 0.5, thickness: 0.5, color: context.vita.divider),
          // Balance strip.
          Container(
            width: double.infinity,
            color: context.vita.pageBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'experience.balance'.trParams({'coins': '$_balance'}),
              style: TextStyle(fontSize: 13, color: context.vita.subText),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? VitaEmpty(
                        icon: Icons.auto_awesome_outlined,
                        title: 'experience.empty'.tr,
                        subtitle: '')
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 0.5,
                            thickness: 0.5,
                            indent: 16,
                            color: context.vita.divider),
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          final key = product['key'] as String? ?? '';
                          final owned = _owned[key] == true;
                          final equipped = _equipped == key;
                          return Container(
                            color: context.vita.surface,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(children: [
                              Text(product['emoji'] as String? ?? '✨',
                                  style: const TextStyle(fontSize: 28)),
                              const SizedBox(width: 13),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        (product['name_key'] as String? ?? key)
                                            .tr,
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: context.vita.text)),
                                    const SizedBox(height: 3),
                                    Text(
                                        (product['description_key']
                                                    as String? ??
                                                '')
                                            .tr,
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: context.vita.subText,
                                            height: 1.35)),
                                  ])),
                              const SizedBox(width: 10),
                              _buildActionButton(context, product,
                                  owned: owned, equipped: equipped),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildActionButton(
      BuildContext context, Map<String, dynamic> product,
      {required bool owned, required bool equipped}) {
    final key = product['key'] as String? ?? '';
    if (equipped) {
      return Text('experience.equipped'.tr,
          style: TextStyle(fontSize: 13, color: context.vita.hint));
    }
    final buying = _buying == key;
    return GestureDetector(
      onTap: (_buying == null && !equipped) ? () => _purchase(product) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: owned ? context.vita.greenTint : context.vita.green,
          borderRadius: BorderRadius.circular(6),
        ),
        child: buying
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(
                owned
                    ? 'experience.equip'.tr
                    : '${product['coins']}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: owned ? context.vita.green : Colors.white),
              ),
      ),
    );
  }
}
