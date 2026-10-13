import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/analytics_service.dart';
import '../../core/config_sync_controller.dart';
import '../../core/notice.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../billing/billing_controller.dart';
import 'experience_flow.dart';

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
  final Future<void> Function(Map<String, dynamic>)? onResult;
  @override
  State<ExperienceSheet> createState() => _ExperienceSheetState();
}

class _ExperienceSheetState extends State<ExperienceSheet> {
  ExperiencePhase _phase = ExperiencePhase.choosing;
  bool _loading = true;
  bool _continuing = false;
  bool _openedGift = false;
  int _balance = 0;
  bool _isSubscribed = false;
  List<Map<String, dynamic>> _products = [];
  Map<String, bool> _owned = {};
  Map<String, dynamic> _companion = {};
  Map<String, dynamic> _scene = {};
  String _category = 'gift';
  String? _selectedKey;
  String? _buying;
  Map<String, dynamic>? _attempt;
  Map<String, dynamic>? _attemptProduct;
  Map<String, dynamic>? _response;
  String? _storageKey;
  String _errorKey = 'experience.flow.failed';
  final _request = TextEditingController();
  Worker? _configWorker;
  Future<void>? _loadFlight;
  bool _needsReload = false;
  bool _restored = false;
  String? _seenVersion;

  String get _name => '${_companion['name'] ?? ''}';
  String get _portrait => '${_companion['portrait_url'] ?? ''}';
  String _group(Map<String, dynamic> product) => switch (product['category']) {
        'gift' => 'gift',
        'date' => 'date',
        _ => 'other'
      };
  String _groupLabel(String group) => 'experience.flow.group.$group'.tr;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<ConfigSyncController>()) {
      final sync = ConfigSyncController.to;
      _seenVersion = sync.revisions['experiences'];
      _configWorker = ever(sync.revisions, (_) {
        final version = sync.revisions['experiences'];
        if (version == _seenVersion) return;
        _seenVersion = version;
        if (_phase != ExperiencePhase.choosing || _loadFlight != null) {
          _needsReload = true;
          return;
        }
        _load();
      });
      sync.refresh();
    }
    _load();
  }

  Future<void> _load() {
    if (_loadFlight != null) return _loadFlight!;
    final next = _loadNow();
    _loadFlight = next;
    return next.whenComplete(() {
      _loadFlight = null;
      if (mounted && _needsReload && _phase == ExperiencePhase.choosing)
        _load();
    });
  }

  Future<void> _loadNow() async {
    _needsReload = false;
    try {
      final raw = await ApiClient.instance
          .get('/v1/companions/${widget.companionId}/experiences');
      if (!mounted) return;
      if (raw is! Map) throw ApiException('experience.flow.failed'.tr);
      final products = (raw['products'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final selection = products
              .where((item) =>
                  item['key'] == (_selectedKey ?? widget.recommendedProductKey))
              .firstOrNull ??
          products
              .where((item) =>
                  item['is_launched'] != false && item['category'] == 'gift')
              .firstOrNull ??
          products.firstOrNull;
      setState(() {
        _products = products;
        _balance = (raw['balance'] as num?)?.toInt() ?? 0;
        _isSubscribed = raw['is_subscribed'] == true;
        _owned = (raw['owned_outfits'] as Map? ?? {})
            .map((key, value) => MapEntry('$key', value == true));
        _companion = raw['companion'] is Map
            ? Map<String, dynamic>.from(raw['companion'])
            : {};
        _scene =
            raw['scene'] is Map ? Map<String, dynamic>.from(raw['scene']) : {};
        _selectedKey = selection?['key'] as String?;
        if (selection != null) _category = _group(selection);
        _loading = false;
      });
      if (!_restored) {
        _restored = true;
        await _restore();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (Get.isRegistered<ConfigSyncController>())
        ConfigSyncController.to.invalidate('experiences');
    }
  }

  Future<void> _restore() async {
    final user = BillingController.to.currentUserID;
    if (user.isEmpty) return;
    _storageKey = 'vita.experience.pending.$user.${widget.companionId}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey!);
      if (raw == null || !mounted) return;
      final saved = jsonDecode(raw);
      if (saved is! Map || saved['request'] is! Map || saved['product'] is! Map)
        return;
      setState(() {
        _attempt = Map<String, dynamic>.from(saved['request']);
        _attemptProduct = Map<String, dynamic>.from(saved['product']);
        _phase = ExperiencePhase.uncertain;
      });
    } catch (_) {}
  }

  Future<void> _persist() async {
    final user = BillingController.to.currentUserID;
    if (user.isEmpty) throw ApiException('experience.flow.failed'.tr);
    _storageKey = 'vita.experience.pending.$user.${widget.companionId}';
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_storageKey!,
        jsonEncode({'request': _attempt, 'product': _attemptProduct})))
      throw ApiException('experience.flow.failed'.tr);
  }

  Future<void> _clearPending() async {
    if (_storageKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey!);
    } catch (_) {}
  }

  Future<void> _purchase(Map<String, dynamic> product) async {
    if (_buying != null || product['is_launched'] == false) return;
    final key = '${product['key']}';
    final owned = _owned[key] == true;
    final coins = owned ? 0 : (product['coins'] as num?)?.toInt() ?? 0;
    if (product['subscription_only'] == true && !_isSubscribed) {
      Navigator.pop(context);
      Get.toNamed('/subscription');
      return;
    }
    if (_balance < coins) {
      Navigator.pop(context);
      Get.toNamed('/credits/buy');
      return;
    }
    final request =
        owned || product['category'] == 'date' ? '' : _request.text.trim();
    if (request.runes.length > 500) return;
    final appointment =
        product['category'] == 'date' ? await _chooseAppointment() : null;
    if (!mounted || product['category'] == 'date' && appointment == null)
      return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.vita.surface,
      builder: (sheetContext) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('experience.flow.confirmTitle'.tr,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: sheetContext.vita.text)),
                    const SizedBox(height: 16),
                    Text('${product['name_key'] ?? key}'.tr,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: sheetContext.vita.text)),
                    if (request.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(request,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: sheetContext.vita.subText))),
                    if (appointment != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(MaterialLocalizations.of(sheetContext)
                                  .formatMediumDate(appointment) +
                              ' ' +
                              TimeOfDay.fromDateTime(appointment)
                                  .format(sheetContext))),
                    const SizedBox(height: 16),
                    Text(
                        'experience.flow.cost'.trParams({
                          'coins': '$coins',
                          'balance': '${_balance - coins}'
                        }),
                        style: TextStyle(
                            fontSize: 15, color: sheetContext.vita.text)),
                    const SizedBox(height: 8),
                    Text(
                        (product['category'] == 'date'
                                ? 'experience.flow.dateCharge'
                                : 'experience.flow.charge')
                            .tr,
                        style: TextStyle(
                            color: sheetContext.vita.subText,
                            fontSize: 12,
                            height: 1.5)),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: Text('experience.flow.confirm'.tr)),
                    TextButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: Text('common.cancel'.tr)),
                  ]))),
    );
    if (confirmed != true || !mounted) return;
    _attemptProduct = Map<String, dynamic>.from(product);
    _attempt = {
      'idempotency_key':
          'experience:${widget.companionId}:${DateTime.now().microsecondsSinceEpoch}',
      'input': <String, dynamic>{
        if (!owned) 'quoted_coins': coins,
        if (request.isNotEmpty) 'custom_request': request,
        if (appointment != null)
          'scheduled_at': appointment.toUtc().toIso8601String()
      }
    };
    try {
      await _persist();
    } catch (_) {
      if (mounted)
        setState(() {
          _phase = ExperiencePhase.failed;
          _errorKey = 'experience.flow.failed';
        });
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final product = _attemptProduct;
    final request = _attempt;
    if (product == null || request == null || _buying != null) return;
    final owner = BillingController.to.currentUserID;
    setState(() {
      _phase = ExperiencePhase.preparing;
      _buying = '${product['key']}';
    });
    try {
      final raw = await ApiClient.instance.post(
          '/v1/companions/${widget.companionId}/experiences/${product['key']}',
          data: request);
      if (!mounted || BillingController.to.currentUserID != owner) return;
      if (raw is! Map || raw['result'] is! Map)
        throw ApiException('experience.flow.uncertain'.tr,
            code: 'settlement_pending');
      final response = Map<String, dynamic>.from(raw);
      await _clearPending();
      if (!mounted) return;
      setState(() {
        _response = response;
        _balance = (response['balance'] as num?)?.toInt() ?? _balance;
        _openedGift = product['category'] != 'gift';
        _phase = ExperiencePhase.ready;
      });
      AnalyticsService.to
          .track('experience_purchased', category: 'billing', properties: {
        'companion_id': widget.companionId,
        'product_key': product['key'],
        'idempotent': raw['idempotent'] == true
      });
      unawaited(BillingController.to.refreshCredits());
    } on ApiException catch (error) {
      if (!mounted || BillingController.to.currentUserID != owner) return;
      final uncertain = experienceNeedsRecovery(error);
      if (!uncertain) await _clearPending();
      if (!mounted) return;
      setState(() {
        _phase = uncertain ? ExperiencePhase.uncertain : ExperiencePhase.failed;
        _errorKey = switch (error.code) {
          'experience_price_changed' => 'experience.flow.priceChanged',
          'experience_failed' || 'spend_refunded' => 'experience.flow.refunded',
          'date_declined' => 'experience.date.declinedSchedule',
          _ => 'experience.flow.failed'
        };
      });
      unawaited(BillingController.to.refreshCredits());
    } catch (_) {
      if (mounted) setState(() => _phase = ExperiencePhase.uncertain);
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  Future<void> _continue() async {
    if (_response == null || _continuing) return;
    setState(() => _continuing = true);
    try {
      if (widget.onResult != null)
        await widget.onResult!(_response!);
      else
        await widget.onCompleted();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        VitaNotice.error(
            'experience.failed'.tr, 'experience.flow.followupFailed'.tr);
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  @override
  void dispose() {
    _configWorker?.dispose();
    _request.dispose();
    super.dispose();
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

  Widget _action(String label, VoidCallback? action) => SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
            onPressed: action,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      );

  Widget _person() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: context.vita.greenTint,
            borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                  width: 64,
                  height: 64,
                  child: _portrait.isEmpty
                      ? Icon(Icons.person_outline, color: context.vita.green)
                      : VitaMediaImage(
                          url: _portrait,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.person_outline)))),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.vita.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                    '${_scene['title'] ?? ''}'.isEmpty
                        ? 'experience.flow.sceneFallback'.tr
                        : '${_scene['title']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.vita.subText, height: 1.4)),
                if ('${_scene['location'] ?? ''}'.isNotEmpty)
                  Text('${_scene['location']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: context.vita.subText, fontSize: 12)),
              ])),
        ]),
      );

  Widget _chooser() {
    final selected =
        _products.where((p) => p['key'] == _selectedKey).firstOrNull;
    final visible = _products.where((p) => _group(p) == _category).toList();
    final custom = selected != null &&
        ['gift', 'photo', 'voice', 'outfit'].contains(selected['category']) &&
        _owned[selected['key']] != true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _person(),
      const SizedBox(height: 20),
      Wrap(
          spacing: 8,
          children: ['gift', 'date', 'other']
              .map((group) => ChoiceChip(
                  label: Text(_groupLabel(group)),
                  selected: _category == group,
                  onSelected: (_) => setState(() {
                        _category = group;
                        _selectedKey = _products
                            .where((p) => _group(p) == group)
                            .firstOrNull?['key'] as String?;
                        _request.clear();
                      })))
              .toList()),
      const SizedBox(height: 12),
      SizedBox(
          height: 128,
          child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final p = visible[index];
                final active = p['key'] == _selectedKey;
                return SizedBox(
                    width: 142,
                    child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => setState(() {
                              _selectedKey = p['key'] as String;
                              _request.clear();
                            }),
                        child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: active
                                    ? context.vita.greenTint
                                    : context.vita.pageBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: active
                                        ? context.vita.green
                                        : context.vita.divider)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                      switch (p['category']) {
                                        'gift' => Icons.card_giftcard_outlined,
                                        'date' => Icons.calendar_month_outlined,
                                        'voice' => Icons.mic_none_outlined,
                                        _ => Icons.auto_awesome_outlined
                                      },
                                      color: active
                                          ? context.vita.green
                                          : context.vita.subText),
                                  const SizedBox(height: 8),
                                  Expanded(
                                      child: Text(
                                          '${p['name_key'] ?? p['key']}'.tr,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: context.vita.text,
                                              fontWeight: FontWeight.w600))),
                                  Text(
                                      p['is_launched'] == false
                                          ? 'experience.comingSoon'.tr
                                          : 'experience.flow.coins'.trParams({
                                              'coins':
                                                  '${_owned[p['key']] == true ? 0 : p['coins'] ?? 0}'
                                            }),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: context.vita.subText,
                                          fontSize: 12)),
                                ]))));
              })),
      const SizedBox(height: 16),
      if (selected != null) ...[
        Text(
            '${selected['description_key'] ?? selected['name_key'] ?? selected['key']}'
                .tr,
            style: TextStyle(color: context.vita.subText, height: 1.5)),
        if (custom) ...[
          const SizedBox(height: 16),
          TextField(
              controller: _request,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                  labelText: 'experience.mediaRequest.title'.tr,
                  hintText: 'experience.mediaRequest.hint'.tr,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16))))
        ],
        const SizedBox(height: 16),
        _action(
            'experience.flow.choose'.tr,
            selected['is_launched'] == false
                ? null
                : () => _purchase(selected)),
      ] else
        _action('common.retry'.tr, _load),
    ]);
  }

  Widget _result() {
    final result =
        Map<String, dynamic>.from(_response?['result'] as Map? ?? {});
    final message =
        result['message'] is Map ? result['message'] as Map : const {};
    final reactionMessage = result['reaction_message'] is Map
        ? result['reaction_message'] as Map
        : const {};
    final text =
        '${result['reaction'] ?? reactionMessage['content'] ?? message['content'] ?? ''}';
    final media = '${message['media_url'] ?? result['media_url'] ?? ''}';
    final category = _attemptProduct?['category'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _person(),
      const SizedBox(height: 22),
      Text(
          (category == 'date'
                  ? 'experience.flow.dateReady'
                  : 'experience.flow.ready')
              .tr,
          style: TextStyle(
              color: context.vita.text,
              fontSize: 22,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      if (!_openedGift)
        SizedBox(
            height: 190,
            child: InkWell(
                onTap: () => setState(() => _openedGift = true),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                    decoration: BoxDecoration(
                        color: context.vita.greenTint,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.card_giftcard_outlined,
                              size: 52, color: context.vita.green),
                          const SizedBox(height: 14),
                          Text('experience.flow.openGift'.tr)
                        ]))))
      else ...[
        if (media.isNotEmpty && category != 'voice')
          ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                  height: 220,
                  child: VitaMediaImage(
                      url: media,
                      placeholderBuilder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, __, ___) => Center(
                          child: Text('experience.flow.mediaInChat'.tr))))),
        if (category == 'voice')
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.headphones_outlined, color: context.vita.green),
              title: Text('experience.flow.voiceReady'.tr)),
        if (text.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(text,
                  style: TextStyle(
                      color: context.vita.text, fontSize: 16, height: 1.6))),
        if ('${result['memory_id'] ?? ''}'.isNotEmpty && category != 'date')
          Text('experience.flow.remembered'.tr,
              style: TextStyle(color: context.vita.subText, fontSize: 12)),
      ],
      const SizedBox(height: 22),
      _action(
          (_openedGift
                  ? (category == 'date'
                      ? 'experience.flow.openDate'
                      : 'experience.flow.continue')
                  : 'experience.flow.openGift')
              .tr,
          _continuing
              ? null
              : () {
                  if (!_openedGift) {
                    setState(() => _openedGift = true);
                  } else {
                    _continue();
                  }
                }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final uncertain = _phase == ExperiencePhase.uncertain;
    return PopScope(
        canPop: _phase != ExperiencePhase.preparing,
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .83,
            child: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: Text('experience.title'.tr,
                                style: TextStyle(
                                    color: context.vita.text,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600))),
                        Text(
                            'experience.flow.coins'
                                .trParams({'coins': '$_balance'}),
                            style: TextStyle(color: context.vita.subText))
                      ]),
                      const SizedBox(height: 18),
                      Expanded(
                          child: SingleChildScrollView(
                              child: _loading
                                  ? const Padding(
                                      padding: EdgeInsets.all(48),
                                      child: Center(
                                          child: CircularProgressIndicator()))
                                  : switch (_phase) {
                                      ExperiencePhase.choosing => _chooser(),
                                      ExperiencePhase.ready => _result(),
                                      ExperiencePhase.preparing =>
                                        Column(children: [
                                          _person(),
                                          const SizedBox(height: 48),
                                          const CircularProgressIndicator(),
                                          const SizedBox(height: 24),
                                          Text('experience.flow.preparing'.tr,
                                              style: TextStyle(
                                                  color: context.vita.text,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 12),
                                          Text(
                                              'experience.flow.preparingHint'
                                                  .tr,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: context.vita.subText,
                                                  height: 1.6))
                                        ]),
                                      _ => Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _person(),
                                              const SizedBox(height: 28),
                                              Text(
                                                  (uncertain
                                                          ? 'experience.flow.uncertain'
                                                          : _errorKey)
                                                      .tr,
                                                  style: TextStyle(
                                                      color: context.vita.text,
                                                      fontSize: 17,
                                                      height: 1.6)),
                                              const SizedBox(height: 24),
                                              _action(
                                                  (uncertain
                                                          ? 'experience.flow.recover'
                                                          : 'experience.flow.chooseAgain')
                                                      .tr, () {
                                                if (uncertain) {
                                                  _submit();
                                                } else {
                                                  setState(() {
                                                    _phase = ExperiencePhase
                                                        .choosing;
                                                    _attempt = null;
                                                    _attemptProduct = null;
                                                    _response = null;
                                                  });
                                                  _load();
                                                }
                                              })
                                            ]),
                                    })),
                    ])))));
  }
}
