import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/api_client.dart';
import '../../core/notice.dart';
import '../../core/theme.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _text = TextEditingController();
  bool _sending = false;
  @override
  void dispose() { _text.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final content = _text.text.trim();
    if (_sending) return;
    if (content.isEmpty || content.runes.length > 2000) {
      VitaNotice.error('feedback.title'.tr, 'feedback.invalid'.tr);
      return;
    }
    setState(() => _sending = true);
    try {
      await ApiClient.instance.post('/v1/feedback', data: {'content': content});
      if (!mounted) return;
      _text.clear();
      VitaNotice.info('feedback.title'.tr, 'feedback.success'.tr);
    } catch (_) {
      if (mounted) VitaNotice.error('feedback.title'.tr, 'feedback.failed'.tr);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vita.pageBg,
    appBar: AppBar(title: Text('feedback.title'.tr)),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      TextField(
        controller: _text,
        enabled: !_sending,
        maxLength: 2000,
        minLines: 8,
        maxLines: 12,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'feedback.hint'.tr,
          border: const OutlineInputBorder(),
          counterText: '${_text.text.runes.length}/2000',
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _sending || _text.text.trim().isEmpty || _text.text.trim().runes.length > 2000 ? null : _submit,
        child: Text((_sending ? 'feedback.sending' : 'feedback.submit').tr),
      ),
    ])),
  );
}
