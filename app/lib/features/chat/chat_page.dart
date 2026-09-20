import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../core/analytics_service.dart';
import '../../shared/widgets.dart';
import '../../core/api_client.dart';
import '../billing/billing_controller.dart';
import 'chat_controller.dart';

/// Chat detail page — message bubbles (user right / companion left),
/// date separators and a WeChat-style input bar.
class ChatPage extends StatefulWidget {
  const ChatPage(
      {super.key,
      required this.companionId,
      required this.name,
      this.companion});

  final String companionId;
  final String name;

  /// Full companion profile map (from the list) — shown in the "more" sheet.
  final Map<String, dynamic>? companion;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController ctrl = Get.put(
    ChatController(companionId: widget.companionId, companionName: widget.name),
    tag: widget.companionId,
  );
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.companion?['friendship_active'] == false) {
      ctrl.accessError.value = 'friendship_inactive';
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    Get.delete<ChatController>(tag: widget.companionId);
    super.dispose();
  }

  void _send() {
    if (ctrl.accessError.value != null) {
      Get.toNamed('/subscription');
      return;
    }
    final text = _input.text;
    ctrl.send(text).then((_) {
      _input.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  Future<void> _sendGift(int coins) async {
    try {
      await ApiClient.instance.post(
          '/v1/companions/${widget.companionId}/gifts',
          data: {'coins': coins});
      await BillingController.to.refreshCredits();
      AnalyticsService.to.track('gift_sent',
          category: 'billing',
          properties: {'companion_id': widget.companionId, 'coins': coins});
      Get.back();
      Get.snackbar('gift.sent.title'.tr,
          'gift.sent.message'.trParams({'coins': '$coins'}));
    } on ApiException catch (e) {
      AnalyticsService.to
          .track('gift_send_failed', category: 'billing', properties: {
        'companion_id': widget.companionId,
        'coins': coins,
        'reason': e.code ?? e.message
      });
      if (e.action == 'open_subscription') {
        Get.back();
        Get.toNamed('/subscription');
      } else {
        Get.snackbar('gift.failed'.tr, e.message);
      }
    }
  }

  void _showCompanionSheet() {
    final c = widget.companion ?? const <String, dynamic>{};
    showModalBottomSheet(
      context: context,
      backgroundColor: context.vita.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  VitaAvatar(
                      name: widget.name,
                      radius: 30,
                      imageUrl: c['portrait_url'] as String?),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.name,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: context.vita.text)),
                      if ((c['city'] as String?)?.isNotEmpty == true)
                        Text(c['city'] as String,
                            style: TextStyle(
                                fontSize: 13, color: context.vita.subText)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SheetInfoRow(
                  icon: Icons.place_outlined,
                  label: 'chat.city'.tr,
                  value: c['city'] as String? ?? ''),
              const SizedBox(height: 4),
              _SheetInfoRow(
                  icon: Icons.work_outline,
                  label: 'chat.occupation'.tr,
                  value: c['occupation'] as String? ?? ''),
              const SizedBox(height: 4),
              _SheetInfoRow(
                  icon: Icons.favorite_outline,
                  label: 'chat.interests'.tr,
                  value: c['interests'] as String? ?? ''),
              const SizedBox(height: 4),
              _SheetInfoRow(
                  icon: Icons.explore,
                  label: 'chat.relationship'.tr,
                  value: (c['relationship_stage'] as String?)?.toUpperCase() ??
                      ''),
              if (c['is_default'] != true) ...[
                const SizedBox(height: 16),
                Text('gift.title'.tr,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.vita.text)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [10, 50, 100]
                      .map((coins) => OutlinedButton(
                            onPressed: () => _sendGift(coins),
                            child: Text(
                                'gift.coins'.trParams({'coins': '$coins'})),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vita.pageBg,
      appBar: AppBar(
        titleSpacing: 4,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 20, color: context.vita.text),
          onPressed: () => Get.back(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VitaAvatar(
                name: widget.name,
                radius: 17,
                imageUrl: widget.companion?['portrait_url'] as String?),
            const SizedBox(width: 9),
            Text(widget.name,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.vita.text)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz, color: context.vita.subText),
            onPressed: _showCompanionSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Obx(() => ctrl.accessError.value == null
              ? const SizedBox.shrink()
              : Container(
                  width: double.infinity,
                  color: context.vita.greenTint,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                      ctrl.accessError.value == 'friendship_inactive'
                          ? 'chat.notFriendsDetail'.tr
                          : 'chat.trialExpired'.tr,
                      style: TextStyle(fontSize: 13, color: context.vita.text),
                    )),
                    TextButton(
                        onPressed: () => Get.toNamed('/subscription'),
                        child: Text('subscription.continue'.tr)),
                  ]),
                )),
          Expanded(child: Obx(() => _buildMessages(ctrl))),
          Obx(() => _buildInputBar(locked: ctrl.accessError.value != null)),
        ],
      ),
    );
  }

  Widget _buildMessages(ChatController ctrl) {
    if (ctrl.loading.value && ctrl.messages.isEmpty) {
      return const Center(
          child: VitaSkeleton(width: 220, height: 44, radius: 14));
    }
    if (ctrl.messages.isEmpty) {
      return VitaEmpty(
        icon: Icons.chat_bubble_outline,
        title: 'chat.sayHello'.tr,
        subtitle: 'chat.sayHelloSub'.tr,
      );
    }

    // Flatten messages with date separators and per-group timestamps.
    final items = <Widget>[];
    DateTime? prevDate;
    for (var i = 0; i < ctrl.messages.length; i++) {
      final m = ctrl.messages[i];
      final dt =
          DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now();
      if (prevDate == null || !isSameDay(dt, prevDate)) {
        items.add(VitaDateChip(label: formatDateSeparator(dt)));
      } else {
        final prev = ctrl.messages[i - 1];
        final prevDt =
            DateTime.tryParse(prev['created_at'] as String? ?? '') ?? dt;
        final sameSender = prev['sender_type'] == m['sender_type'];
        final closeInTime = dt.difference(prevDt) < const Duration(minutes: 10);
        if (!sameSender || !closeInTime) {
          items.add(Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(formatClock(dt),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF999999))),
            ),
          ));
        }
      }
      prevDate = dt;

      final isUser = m['sender_type'] == 'user';
      final content = m['content'] as String? ?? '';
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                VitaAvatar(
                    name: widget.name,
                    radius: 20,
                    imageUrl: widget.companion?['portrait_url'] as String?),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.66,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: isUser
                        ? context.vita.bubbleGreen
                        : context.vita.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: isUser
                        ? null
                        : Border.all(color: context.vita.divider, width: 0.5),
                  ),
                  child: Text(
                    content,
                    style: TextStyle(
                        fontSize: 16, color: context.vita.text, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: items,
    );
  }

  Widget _buildInputBar({required bool locked}) {
    return Container(
      decoration: BoxDecoration(
        color: context.vita.pageBg,
        border:
            Border(top: BorderSide(color: context.vita.divider, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !locked,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: TextStyle(
                  fontSize: 16, color: context.vita.text, height: 1.4),
              decoration: InputDecoration(
                hintText: locked ? 'chat.cannotSend'.tr : 'chat.message'.tr,
                hintStyle: TextStyle(color: context.vita.hint, fontSize: 15),
                filled: true,
                fillColor: context.vita.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: locked ? () => Get.toNamed('/subscription') : _send,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(64, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text('common.send'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetInfoRow extends StatelessWidget {
  const _SheetInfoRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.vita.subText),
        const SizedBox(width: 10),
        SizedBox(
          width: 84,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.vita.subText)),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: TextStyle(fontSize: 14, color: context.vita.text),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
