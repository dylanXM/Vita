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
      final selected =
          products.where((item) => item['key'] == _selectedKey).firstOrNull;
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
    final visible =
        _products.where((item) => _categoryFor(item) == _category).toList();
    final selected =
        visible.where((item) => item['key'] == _selectedKey).firstOrNull ??
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    color: context.vita.greenTint,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    'experience.balance'.trParams({'coins': '$_balance'}),
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
                                .map((group) =>
                                    _buildCategoryTab(context, group))
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
                                  _buildPreview(context, selected),
                              ],
                            ),
                          ),
                        ),
                        if (selected != null)
                          _buildPurchaseBar(context, selected),
                      ]),
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

  String _categoryFor(Map<String, dynamic>? product) =>
      switch (product?['category']) {
        'gift' => 'gift',
        'date' => 'date',
        _ => 'other',
      };

  String _categoryLabel(String category) => switch (category) {
        'gift' => 'experience.collection.gifts'.tr,
        'date' => 'experience.collection.dates'.tr,
        _ => 'experience.collection.more'.tr,
      };

  Widget _buildCategoryTab(BuildContext context, String category) {
    final active = _category == category;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: _buying != null
              ? null
              : () {
                  final next = _products
                      .where((item) => _categoryFor(item) == category)
                      .firstOrNull;
                  if (next == null) return;
                  setState(() {
                    _category = category;
                    _selectedKey = next['key'] as String?;
                  });
                },
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? context.vita.greenTint : context.vita.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                  color: active ? context.vita.green : context.vita.divider),
            ),
            child: Text(_categoryLabel(category),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: active ? context.vita.green : context.vita.subText,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext context, Map<String, dynamic> product) {
    final key = product['key'] as String? ?? '';
    final selected = _selectedKey == key;
    return InkWell(
      onTap: _buying != null ? null : () => setState(() => _selectedKey = key),
      borderRadius: BorderRadius.circular(17),
      child: Container(
        width: 102,
        height: 90,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: selected ? context.vita.greenTint : context.vita.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
              color: selected ? context.vita.green : context.vita.divider,
              width: selected ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_productIcon(product),
              size: 24,
              color: selected ? context.vita.green : context.vita.text),
          const Spacer(),
          Text((product['name_key'] as String? ?? key).tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: context.vita.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text('gift.coins'.trParams({'coins': "${product['coins']}"}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.vita.subText, fontSize: 10.5)),
        ]),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, Map<String, dynamic> product) {
    final key = product['key'] as String? ?? '';
    final gift = _categoryFor(product) == 'gift';
    final date = _categoryFor(product) == 'date';
    return Container(
      height: 306,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.vita.greenTint, context.vita.surface],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.vita.green.withValues(alpha: .32)),
      ),
      child: Stack(children: [
        Positioned(
          right: -52,
          top: -64,
          child: Container(
            width: 210,
            height: 210,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: context.vita.green.withValues(alpha: .16))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(
                width: 66,
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: context.vita.surface.withValues(alpha: .76),
                    borderRadius: BorderRadius.circular(21)),
                child: Icon(_productIcon(product),
                    color: context.vita.green, size: 34),
              ),
            ]),
            const Spacer(),
            Text((product['name_key'] as String? ?? key).tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.vita.text,
                    fontSize: 27,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text((product['description_key'] as String? ?? '').tr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.vita.subText, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            Divider(height: 1, color: context.vita.divider),
            const SizedBox(height: 13),
            if (gift) ...[
              _previewResult(context, Icons.chat_bubble_outline_rounded,
                  'experience.gift.chatResult'.tr),
              const SizedBox(height: 9),
              _previewResult(context, Icons.favorite_border_rounded,
                  'experience.gift.bondResult'.tr),
            ] else if (date)
              _previewResult(context, Icons.event_available_rounded,
                  'experience.date.value'.tr,
                  maxLines: 2)
            else
              Text(_categoryLabel('other'),
                  style: TextStyle(
                      color: context.vita.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _previewResult(BuildContext context, IconData icon, String label,
      {int maxLines = 1}) {
    return Row(children: [
      Icon(icon, color: context.vita.green, size: 17),
      const SizedBox(width: 9),
      Expanded(
        child: Text(label,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.vita.text, fontSize: 12.5)),
      ),
    ]);
  }

  Widget _buildPurchaseBar(BuildContext context, Map<String, dynamic> product) {
    final key = product['key'] as String? ?? '';
    final owned = _owned[key] == true;
    final equipped = _equipped == key;
    final gift = _categoryFor(product) == 'gift';
    final price = 'gift.coins'.trParams({'coins': "${product['coins']}"});
    final label = equipped
        ? 'experience.equipped'.tr
        : owned
            ? 'experience.equip'.tr
            : gift
                ? 'experience.gift.send'
                    .trParams({'coins': "${product['coins']}"})
                : "${'experience.use'.tr} · $price";
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
          color: context.vita.surface,
          border: Border(top: BorderSide(color: context.vita.divider))),
      child: ElevatedButton(
        onPressed:
            _buying != null || equipped ? null : () => _purchase(product),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _buying == key
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
