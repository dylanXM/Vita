import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
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
      this.recommendedProductKey,
      this.onResult});

  final String companionId;
  final String? recommendedProductKey;
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
      final products = (data['products'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final recommendedKey = widget.recommendedProductKey;
      if (recommendedKey != null) {
        final index =
            products.indexWhere((item) => item['key'] == recommendedKey);
        if (index > 0) {
          products.insert(0, products.removeAt(index));
        }
      }
      setState(() {
        _balance = data['balance'] as int? ?? 0;
        _products = products;
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
        VitaNotice.error('experience.failed'.tr, error.message);
      }
    }
  }

  Future<void> _purchase(Map<String, dynamic> product) async {
    final key = product['key'] as String? ?? '';
    final coins = product['coins'] as int? ?? 0;
    final owned = _owned[key] == true;
    final appointment =
        product['category'] == 'date' ? await _chooseAppointment() : null;
    if (product['category'] == 'date' && appointment == null) return;
    if (!mounted) return;
    final appointmentLabel = appointment == null
        ? ''
        : '${MaterialLocalizations.of(context).formatMediumDate(appointment)} '
            '${TimeOfDay.fromDateTime(appointment).format(context)}';
    final confirmation = owned
        ? 'experience.equipConfirm'.tr
        : product['category'] == 'gift'
            ? 'experience.gift.confirm'.trParams({'coins': '$coins'})
            : 'experience.confirm'.trParams({'coins': '$coins'});
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text((product['name_key'] as String? ?? key).tr),
        content: Text(appointment == null
            ? confirmation
            : '${'moment.scheduled'.trParams({
                    'time': appointmentLabel
                  })}\n$confirmation'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common.cancel'.tr,
                  style: const TextStyle(color: CupertinoColors.systemGrey))),
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
          'input': <String, dynamic>{
            if (appointment != null)
              'scheduled_at': appointment.toUtc().toIso8601String(),
          }
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
      if (product['category'] == 'gift') {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final result = data is Map ? data['result'] : null;
      if (!mounted ||
          (widget.onResult != null &&
              result is Map &&
              result['event_id'] is String)) {
        return;
      }
      VitaNotice.success('experience.done'.tr,
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
      } else if (error.code == 'invalid_appointment') {
        VitaNotice.error(
            'experience.failed'.tr, 'experience.appointmentInvalid'.tr);
      } else if (error.code == 'appointment_unavailable') {
        VitaNotice.error(
            'experience.failed'.tr, 'experience.appointmentBusy'.tr);
      } else {
        VitaNotice.error('experience.failed'.tr, error.message);
      }
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  Future<DateTime?> _chooseAppointment() async {
    final now = DateTime.now();
    final earliest = now.add(const Duration(minutes: 5));
    final latest = now.add(const Duration(days: 30));
    var selected = now.add(const Duration(hours: 1));
    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 330,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Text('experience.chooseTime'.tr,
                      style: TextStyle(
                          color: sheetContext.vita.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, selected),
                  child: Text('common.save'.tr),
                ),
              ]),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: selected,
                minimumDate: earliest,
                maximumDate: latest,
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasGifts = _products.any((product) => product['category'] == 'gift');
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
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: _products.length + (hasGifts ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (hasGifts && index == 0) {
                            return _buildGiftIntro(context);
                          }
                          final product = _products[index - (hasGifts ? 1 : 0)];
                          final key = product['key'] as String? ?? '';
                          final owned = _owned[key] == true;
                          final equipped = _equipped == key;
                          final isDate = product['category'] == 'date';
                          if (product['category'] == 'gift') {
                            return _buildGiftCard(context, product);
                          }
                          return Container(
                            decoration: BoxDecoration(
                              color: context.vita.surface,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: context.vita.greenTint,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                        product['emoji'] as String? ?? '✨',
                                        style: const TextStyle(fontSize: 26)),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            (product['name_key'] as String? ??
                                                    key)
                                                .tr,
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
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
                                      ],
                                    ),
                                  ),
                                ]),
                                if (isDate) ...[
                                  const SizedBox(height: 12),
                                  Text('experience.date.value'.tr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: context.vita.green,
                                      )),
                                ],
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _buildActionButton(context, product,
                                      owned: owned, equipped: equipped),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildGiftIntro(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 5, 4, 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('experience.gift.headline'.tr,
            style: TextStyle(
                color: context.vita.text,
                fontSize: 21,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text('experience.gift.intro'.tr,
            style: TextStyle(
                color: context.vita.subText, fontSize: 13, height: 1.4)),
      ]),
    );
  }

  Widget _buildGiftCard(BuildContext context, Map<String, dynamic> product) {
    final emoji = product['emoji'] as String? ?? '🎁';
    final key = product['key'] as String? ?? '';
    return Container(
      height: 190,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      decoration: BoxDecoration(
        color: context.vita.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vita.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((product['name_key'] as String? ?? key).tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.vita.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text((product['description_key'] as String? ?? '').tr,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.vita.subText,
                      fontSize: 12.5,
                      height: 1.35)),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: context.vita.greenTint,
                borderRadius: BorderRadius.circular(18)),
            child: Text(emoji, style: const TextStyle(fontSize: 34)),
          ),
        ]),
        const Spacer(),
        Row(children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 15, color: context.vita.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text('experience.gift.chatResult'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.vita.subText, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          Icon(Icons.favorite_border_rounded,
              size: 15, color: context.vita.green),
          const SizedBox(width: 6),
          Expanded(
            child: Text('experience.gift.bondResult'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.vita.subText, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          _buildActionButton(context, product,
              owned: false, equipped: false, gift: true),
        ]),
      ]),
    );
  }

  Widget _buildActionButton(BuildContext context, Map<String, dynamic> product,
      {required bool owned, required bool equipped, bool gift = false}) {
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
                    : gift
                        ? 'experience.gift.send'
                            .trParams({'coins': '${product['coins']}'})
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
