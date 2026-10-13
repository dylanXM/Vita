import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/notice.dart';
import '../../core/theme.dart';

/// Drafts come from the saved conversation. Only an explicit confirmation
/// creates the persistent keepsake; this component never purchases anything.
class ExperienceDecisionPanel extends StatefulWidget {
  const ExperienceDecisionPanel(
      {super.key,
      required this.companionId,
      this.eventId,
      this.spendId,
      this.proposalMessage,
      required this.busy,
      this.onConfirmingChanged,
      this.compact = true});
  final String companionId;
  final String? eventId, spendId;
  final Map<String, dynamic>? proposalMessage;
  final bool busy, compact;
  final ValueChanged<bool>? onConfirmingChanged;
  @override
  State<ExperienceDecisionPanel> createState() =>
      _ExperienceDecisionPanelState();
}

class _ExperienceDecisionPanelState extends State<ExperienceDecisionPanel> {
  Map<String, dynamic>? _outcome;
  bool _loading = true, _loadFailed = false, _confirming = false;
  Map<String, dynamic> get _reference => {
        if (widget.eventId != null) 'event_id': widget.eventId,
        if (widget.spendId != null) 'spend_id': widget.spendId
      };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    try {
      final raw = await ApiClient.instance.get(
          '/v1/companions/${widget.companionId}/experience-outcome',
          query: _reference,
          receiveTimeout: const Duration(seconds: 5));
      if (!mounted) return;
      if (raw is! Map) throw StateError('invalid response');
      setState(() {
        _outcome = raw['outcome'] is Map
            ? Map<String, dynamic>.from(raw['outcome'])
            : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
    }
  }

  Future<void> _confirm(Map<String, dynamic> proposal) async {
    if (_confirming || widget.busy || _loading || _loadFailed) return;
    final proposalID = widget.proposalMessage?['id'];
    if (proposalID is! String) return;
    var title = '${proposal['title'] ?? ''}';
    final accepted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: context.vita.surface,
        builder: (sheetContext) => SafeArea(
            top: false,
            child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20,
                    MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('experience.journey.confirmTitle'.tr,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Text('${proposal['decision'] ?? ''}',
                          style: const TextStyle(fontSize: 16, height: 1.5)),
                      const SizedBox(height: 16),
                      TextFormField(
                          initialValue: title,
                          maxLength: 80,
                          onChanged: (value) => title = value,
                          decoration: InputDecoration(
                              labelText: 'experience.journey.name'.tr)),
                      const SizedBox(height: 12),
                      Text('experience.journey.confirmHint'.tr,
                          style: TextStyle(
                              color: sheetContext.vita.subText, height: 1.5)),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () {
                            final value = title.trim();
                            if (value.isEmpty || value.runes.length > 80) {
                              VitaNotice.error('experience.failed'.tr,
                                  'experience.journey.nameInvalid'.tr);
                              return;
                            }
                            Navigator.pop(sheetContext, true);
                          },
                          child: Text('experience.journey.confirm'.tr)),
                    ]))));
    if (accepted != true || !mounted || widget.busy) return;
    title = title.trim();
    if (title.isEmpty) return;
    setState(() => _confirming = true);
    widget.onConfirmingChanged?.call(true);
    try {
      final raw = await ApiClient.instance.post(
          '/v1/companions/${widget.companionId}/experience-outcome',
          data: {
            ..._reference,
            'proposal_message_id': proposalID,
            'title': title
          });
      if (!mounted) return;
      if (raw is! Map || raw['outcome'] is! Map)
        throw StateError('invalid confirmation');
      setState(() => _outcome = Map<String, dynamic>.from(raw['outcome']));
    } catch (_) {
      if (mounted) {
        VitaNotice.error(
            'experience.failed'.tr, 'experience.journey.confirmFailed'.tr);
        await _load();
      }
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
        widget.onConfirmingChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.proposalMessage?['payload'];
    final draft = payload is Map && payload['experience_proposal'] is Map
        ? Map<String, dynamic>.from(payload['experience_proposal'])
        : null;
    final goal = payload is Map ? '${payload['scene_goal'] ?? ''}' : '';
    final challenge =
        payload is Map ? '${payload['scene_challenge'] ?? ''}' : '';
    if (_loading)
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator());
    if (_loadFailed)
      return TextButton(
          onPressed: _load, child: Text('experience.journey.retryLoad'.tr));
    final content = _outcome ?? draft;
    if (content == null && goal.isEmpty && challenge.isEmpty)
      return const SizedBox.shrink();
    final saved = _outcome != null;
    if (widget.compact)
      return SizedBox(
          height: 44,
          child: TextButton.icon(
            onPressed: !saved && content != null && widget.busy
                ? null
                : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    backgroundColor: context.vita.surface,
                    builder: (sheetContext) => SafeArea(
                        top: false,
                        child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(sheetContext).height *
                                        .7),
                            child: SingleChildScrollView(
                                child: _card(sheetContext, content, goal,
                                    challenge, saved))))),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(
                saved
                    ? Icons.bookmark_border
                    : content != null
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                size: 18),
            label: Text(
                (saved
                        ? 'experience.journey.keepsake'
                        : content != null
                            ? 'experience.journey.review'
                            : 'experience.journey.goal')
                    .tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ));
    return _card(context, content, goal, challenge, saved);
  }

  Widget _card(BuildContext context, Map<String, dynamic>? content, String goal,
          String challenge, bool saved) =>
      Container(
          margin: const EdgeInsets.symmetric(vertical: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: context.vita.surface,
              borderRadius: BorderRadius.circular(20)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                (saved
                        ? 'experience.journey.keepsake'
                        : 'experience.journey.goal')
                    .tr,
                style: TextStyle(
                    color: context.vita.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (content == null) ...[
              if (goal.isNotEmpty)
                Text(goal,
                    style: TextStyle(
                        color: context.vita.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
              if (challenge.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(challenge,
                        style: TextStyle(
                            color: context.vita.subText, height: 1.5)))
            ],
            if (content != null) ...[
              Text('${content['title'] ?? ''}',
                  style: TextStyle(
                      color: context.vita.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text('${content['challenge'] ?? ''}',
                  style: TextStyle(color: context.vita.subText, height: 1.5)),
              const SizedBox(height: 12),
              Text('${content['decision'] ?? ''}',
                  style: TextStyle(
                      color: context.vita.text, fontSize: 16, height: 1.5)),
              const SizedBox(height: 12),
              Text('${content['note'] ?? ''}',
                  style: TextStyle(color: context.vita.text, height: 1.6)),
              const SizedBox(height: 16),
              if (saved)
                Text('experience.journey.saved'.tr,
                    style: TextStyle(color: context.vita.green, fontSize: 12))
              else
                FilledButton(
                    onPressed: widget.busy || _confirming
                        ? null
                        : () async {
                            await _confirm(content);
                            if (widget.compact &&
                                _outcome != null &&
                                context.mounted) Navigator.pop(context);
                          },
                    child: Text('experience.journey.review'.tr)),
            ],
          ]));
}
