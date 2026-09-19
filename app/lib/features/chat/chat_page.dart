import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'chat_controller.dart';

/// Chat detail page — message bubbles (user right / companion left) and a
/// WeChat-style input bar.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.companionId, required this.name});

  final String companionId;
  final String name;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VitaColors.pageBg,
      appBar: AppBar(
        title: Text(widget.name),
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
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.messages.isEmpty) {
      return const VitaEmpty(
        icon: Icons.chat_bubble_outline,
        title: 'Say hello',
        subtitle: 'Start the conversation with your companion',
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: ctrl.messages.length,
      itemBuilder: (context, i) {
        final m = ctrl.messages[i];
        final isUser = m['sender_type'] == 'user';
        final content = m['content'] as String? ?? '';
        final time = m['created_at'] as String?;
        final when = time != null ? formatClock(DateTime.tryParse(time) ?? DateTime.now()) : '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                VitaAvatar(name: widget.name, radius: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.62,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: isUser ? VitaColors.bubbleGreen : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(8),
                          topRight: const Radius.circular(8),
                          bottomLeft: Radius.circular(isUser ? 8 : 2),
                          bottomRight: Radius.circular(isUser ? 2 : 8),
                        ),
                        border: isUser ? null : Border.all(color: VitaColors.divider),
                      ),
                      child: Text(
                        content,
                        style: const TextStyle(fontSize: 16, color: VitaColors.text, height: 1.35),
                      ),
                    ),
                    if (when.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(when, style: TextStyle(fontSize: 11, color: VitaColors.subText.withValues(alpha: 0.8))),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(hintText: 'Message'),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: _send,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(64, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}
