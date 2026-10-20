import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

class ExperienceSlot {
  const ExperienceSlot(this.start, this.end);
  final DateTime start, end;
}

List<ExperienceSlot> parseExperienceSlots(dynamic raw) {
  if (raw is! Map || raw['slots'] is! List) return [];
  final slots = <ExperienceSlot>[];
  final serverTime = DateTime.tryParse('${raw['server_time'] ?? ''}');
  for (final item in (raw['slots'] as List).whereType<Map>()) {
    final start = DateTime.tryParse('${item['starts_at'] ?? ''}');
    final end = DateTime.tryParse('${item['ends_at'] ?? ''}');
    if (start == null ||
        end == null ||
        !end.isAfter(start) ||
        serverTime != null &&
            !start.isAfter(serverTime.add(const Duration(minutes: 5))))
      continue;
    if (slots.any((s) => s.start.isAtSameMomentAs(start))) continue;
    slots.add(ExperienceSlot(start.toUtc(), end.toUtc()));
  }
  slots.sort((a, b) => a.start.compareTo(b.start));
  return slots.take(12).toList();
}

class ExperienceSlotPicker extends StatefulWidget {
  const ExperienceSlotPicker(
      {super.key, required this.companionId, required this.productKey});
  final String companionId, productKey;
  @override
  State<ExperienceSlotPicker> createState() => _ExperienceSlotPickerState();
}

class _ExperienceSlotPickerState extends State<ExperienceSlotPicker> {
  bool _loading = true, _failed = false;
  List<ExperienceSlot> _slots = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final raw = await ApiClient.instance.get(
          '/v1/companions/${widget.companionId}/experiences/${widget.productKey}/slots',
          receiveTimeout: const Duration(seconds: 5));
      if (!mounted) return;
      if (raw is! Map || raw['slots'] is! List)
        throw StateError('invalid slots');
      setState(() {
        _slots = parseExperienceSlots(raw);
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .64,
      child: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('experience.slots.title'.tr,
                        style: TextStyle(
                            color: context.vita.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('experience.slots.hint'.tr,
                        style: TextStyle(
                            color: context.vita.subText, height: 1.5)),
                    const SizedBox(height: 16),
                    Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _failed || _slots.isEmpty
                                ? Center(
                                    child: Text(
                                        (_failed
                                                ? 'experience.slots.failed'
                                                : 'experience.slots.empty')
                                            .tr,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: context.vita.subText,
                                            height: 1.5)))
                                : ListView.separated(
                                    itemCount: _slots.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final slot = _slots[index];
                                      final start = slot.start.toLocal(),
                                          end = slot.end.toLocal();
                                      final local =
                                          MaterialLocalizations.of(context);
                                      final day = local.formatMediumDate(start);
                                      final ending = DateUtils.isSameDay(
                                              start, end)
                                          ? ''
                                          : '${local.formatMediumDate(end)} ';
                                      return SizedBox(
                                          height: 76,
                                          child: Material(
                                              color: context.vita.greenTint,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  onTap: () => Navigator.pop(
                                                      context, slot.start),
                                                  child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 16),
                                                      child: Row(children: [
                                                        Expanded(
                                                            child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                              Text(day,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: TextStyle(
                                                                      color: context
                                                                          .vita
                                                                          .text,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600)),
                                                              const SizedBox(
                                                                  height: 6),
                                                              Text(
                                                                  '${TimeOfDay.fromDateTime(start).format(context)} – $ending${TimeOfDay.fromDateTime(end).format(context)}',
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: TextStyle(
                                                                      color: context
                                                                          .vita
                                                                          .subText))
                                                            ])),
                                                        Icon(
                                                            Icons.chevron_right,
                                                            color: context
                                                                .vita.green)
                                                      ])))));
                                    })),
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: _loading ? null : _load,
                        child: Text('experience.slots.refresh'.tr)),
                  ]))));
}
