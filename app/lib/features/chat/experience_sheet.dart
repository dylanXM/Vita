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
  String _category = 'gift';
  String? _selectedKey;

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
      final selected = products.where((item) => item['key'] == _selectedKey).firstOrNull;
      final recommended = recommendedKey == null
          ? null
          : products.where((item) => item['key'] == recommendedKey).firstOrNull;
      final initial = selected ??
          recommended ??
          products.where((item) => item['category'] == 'gift').firstOrNull ??
          products.firstOrNull;
      setState(() {
        _balance = data['balance'] as int? ?? 0;
        _products = products;
        _owned = (data['owned_outfits'] as Map? ?? const {})
            .map((key, value) => MapEntry('$key', value == true));
        _equipped = data['equipped_outfit'] as String? ?? '';
        _selectedKey = initial?['key'] as String?;
        _category = _categoryFor(initial);
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
    final groups = ['gift', 'date', 'other']
        .where((group) => _products.any((item) => _categoryFor(item) == group))
        .toList();
    final visible = _products
        .where((item) => _categoryFor(item) == _category)
        .toList();
    final selected = visible.where((item) => item['key'] == _selectedKey).firstOrNull ??
        visible.firstOrNull;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              Expanded(
                child: Text('experience.title'.tr,
                    style: TextStyle(
                        color: context.vita.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    color: context.vita.greenTint,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('experience.balance'.trParams({'coins': '$_balance'}),
                    style: TextStyle(
                        color: context.vita.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? VitaEmpty(
                        icon: Icons.auto_awesome_outlined,
                        title: 'experience.empty'.tr,
                        subtitle: '')
                    : Column(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: groups
                                .map((group) => _buildCategoryTab(context, group))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 90,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: visible.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 9),
                                    itemBuilder: (context, index) =>
                                        _buildOption(context, visible[index]),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (selected != null)
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    child: _buildPreview(context, selected,
                                        index: visible.indexOf(selected) + 1,
                                        total: visible.length),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (selected != null) _buildPurchaseBar(context, selected),
                      ),
          ),
        ]),
      ),
    );
  }

  IconData _productIcon(Map<String, dynamic> product) {
    return switch (product['key']) {
      'gift_coffee' || 'date_coffee' => Icons.local_cafe_rounded,
      'gift_flowers' => Icons.local_florist_rounded,
      'gift_cake' => Icons.cake_rounded,
      'gift_keepsake' => Icons.redeem_rounded,
      'date_movie' => Icons.movie_rounded,
      'date_dinner' => Icons.restaurant_rounded,
      'life_photo' => Icons.photo_camera_rounded,
      'voice_reply' => Icons.graphic_eq_rounded,
      'memory_card' => Icons.auto_stories_rounded,
      'outfit_casual' ||
      'outfit_evening' ||
      'outfit_travel' =>
        Icons.checkroom_rounded,
      _ => Icons.auto_awesome_rounded,
    };
  }

  Widget _buildProductCard(BuildContext context, Map<String, dynamic> product) {
    final key = product['key'] as String? ?? '';
    final gift = product['category'] == 'gift';
    final date = product['category'] == 'date';
    final owned = _owned[key] == true;
    final equipped = _equipped == key;
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
            child: Icon(_productIcon(product),
                size: 30, color: context.vita.green),
          ),
        ]),
        const Spacer(),
        if (gift) ...[
          _buildOutcome(context, Icons.chat_bubble_outline_rounded,
              'experience.gift.chatResult'.tr),
          const SizedBox(height: 7),
        ] else if (date) ...[
          _buildOutcome(context, Icons.event_available_rounded,
              'experience.date.value'.tr,
              maxLines: 2),
          const SizedBox(height: 7),
        ],
        Row(children: [
          if (gift)
            Expanded(
                child: _buildOutcome(context, Icons.favorite_border_rounded,
                    'experience.gift.bondResult'.tr))
          else
            const Spacer(),
          const SizedBox(width: 8),
          _buildActionButton(context, product,
              owned: owned, equipped: equipped, gift: gift),
        ]),
      ]),
    );
  }

  Widget _buildOutcome(BuildContext context, IconData icon, String text,
      {int maxLines = 1}) {
    return Row(children: [
      Icon(icon, size: 15, color: context.vita.green),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.vita.subText, fontSize: 12)),
      ),
    ]);
  }

  Widget _buildActionButton(BuildContext context, Map<String, dynamic> product,
      {required bool owned, required bool equipped, bool gift = false}) {
    final key = product['key'] as String? ?? '';
    final price = 'gift.coins'.trParams({'coins': '${product['coins']}'});
    if (equipped) {
      return Text('experience.equipped'.tr,
          style: TextStyle(fontSize: 13, color: context.vita.hint));
    }
    final buying = _buying == key;
    return GestureDetector(
      onTap: (_buying == null && !equipped) ? () => _purchase(product) : null,
      child: Container(
        constraints: const BoxConstraints(minWidth: 108, minHeight: 36),
        alignment: Alignment.center,
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
                        : '${'experience.use'.tr} · $price',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: owned ? context.vita.green : Colors.white),
              ),
      ),
    );
  }
}
