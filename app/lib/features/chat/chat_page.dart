import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'chat_controller.dart';

/// Chat detail page — message bubbles (user right / companion left),
/// date separators and a WeChat-style input bar.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.companionId, required this.name, this.companion});

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
  );
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
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
                decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  VitaAvatar(name: widget.name, radius: 30),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.vita.text)),
                      if ((c['city'] as String?)?.isNotEmpty == true)
                        Text(c['city'] as String, style: TextStyle(fontSize: 13, color: context.vita.subText)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SheetInfoRow(icon: Icons.place_outlined, label: 'City', value: c['city'] as String? ?? ''),
              const SizedBox(height: 4),
              _SheetInfoRow(icon: Icons.work_outline, label: 'Occupation', value: c['occupation'] as String? ?? ''),
              const SizedBox(height: 4),
              _SheetInfoRow(icon: Icons.favorite_outline, label: 'Interests', value: c['interests'] as String? ?? ''),
              const SizedBox(height: 4),
              _SheetInfoRow(icon: Icons.explore, label: 'Relationship', value: (c['relationship_stage'] as String?)?.toUpperCase() ?? ''),
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
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: context.vita.text),
          onPressed: () => Get.back(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VitaAvatar(name: widget.name, radius: 17),
            const SizedBox(width: 9),
            Text(widget.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.vita.text)),
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
          Expanded(child: Obx(() => _buildMessages(ctrl))),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessages(ChatController ctrl) {
    if (ctrl.loading.value && ctrl.messages.isEmpty) {
      return const Center(child: VitaSkeleton(width: 220, height: 44, radius: 14));
    }
    if (ctrl.messages.isEmpty) {
      return const VitaEmpty(
        icon: Icons.chat_bubble_outline,
        title: 'Say hello',
        subtitle: 'Start the conversation with your companion',
      );
    }

    // Flatten messages with date separators and per-group timestamps.
    final items = <Widget>[];
    DateTime? prevDate;
    for (var i = 0; i < ctrl.messages.length; i++) {
      final m = ctrl.messages[i];
      final dt = DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now();
      if (prevDate == null || !isSameDay(dt, prevDate)) {
        items.add(VitaDateChip(label: formatDateSeparator(dt)));
      } else {
        final prev = ctrl.messages[i - 1];
        final prevDt = DateTime.tryParse(prev['created_at'] as String? ?? '') ?? dt;
        final sameSender = prev['sender_type'] == m['sender_type'];
        final closeInTime = dt.difference(prevDt) < const Duration(minutes: 10);
        if (!sameSender || !closeInTime) {
          items.add(Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(formatClock(dt), style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
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
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                VitaAvatar(name: widget.name, radius: 20),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.66,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: isUser ? context.vita.bubbleGreen : context.vita.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isUser ? 14 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 14),
                    ),
                    boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 1))],
                  ),
                  child: Text(
                    content,
                    style: TextStyle(fontSize: 16, color: context.vita.text, height: 1.4),
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

  Widget _buildInputBar() {
    return Container(
      color: context.vita.surface,
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: TextStyle(fontSize: 16, color: context.vita.text, height: 1.4),
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: TextStyle(color: context.vita.hint, fontSize: 15),
                filled: true,
                fillColor: context.vita.pageBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: context.vita.green, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetInfoRow extends StatelessWidget {
  const _SheetInfoRow({required this.icon, required this.label, required this.value});

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
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.vita.subText)),
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
