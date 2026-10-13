import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/notice.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import 'chat_controller.dart';
import 'shared_experience_stage.dart';

class ExperienceEncounterPage extends StatefulWidget {
  const ExperienceEncounterPage(
      {super.key,
      required this.companionId,
      required this.name,
      this.portrait,
      required this.response});
  final String companionId, name;
  final String? portrait;
  final Map<String, dynamic> response;
  @override
  State<ExperienceEncounterPage> createState() =>
      _ExperienceEncounterPageState();
}

class _ExperienceEncounterPageState extends State<ExperienceEncounterPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _player = AudioPlayer();
  late final ChatController _chat;
  late final String _tag;
  File? _audioFile;
  bool _audioLoading = false;
  bool _playing = false;
  StreamSubscription<void>? _audioCompleted;
  Map get _result => widget.response['result'] as Map? ?? {};
  String get _spend => '${_result['spend_id'] ?? ''}';
  Map get _message => _result['message'] as Map? ?? {};
  String get _media => '${_message['media_url'] ?? ''}';
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tag = 'experience-${identityHashCode(this)}';
    final controller = ChatController(
        companionId: widget.companionId,
        companionName: widget.name,
        pollInterval: const Duration(seconds: 10));
    controller.isVisible = () =>
        Get.isRegistered<AuthController>() &&
        AuthController.to.profile.value != null &&
        mounted &&
        _foreground &&
        (ModalRoute.of(context)?.isCurrent ?? false);
    _chat = Get.put(controller, tag: _tag);
    _audioCompleted = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _chat.poll();
    if (state != AppLifecycleState.resumed) {
      _player.pause();
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _play() async {
    if (_audioLoading || _media.isEmpty) return;
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _audioLoading = true);
    try {
      final resolved = _media.startsWith('http')
          ? _media
          : '${vitaApiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}${_media.startsWith('/') ? _media : '/$_media'}';
      if (Uri.tryParse(resolved)?.path.startsWith('/v1/media/') == true) {
        if (_audioFile == null) {
          final response = await ApiClient.instance.dio.get<List<int>>(resolved,
              options: Options(responseType: ResponseType.bytes));
          if (!mounted) return;
          final bytes = response.data;
          if (bytes == null || bytes.isEmpty) throw StateError('empty audio');
          final directory = await getTemporaryDirectory();
          if (!mounted) return;
          _audioFile = File(
              '${directory.path}/vita_experience_${identityHashCode(this)}.m4a');
          await _audioFile!.writeAsBytes(bytes, flush: true);
        }
        if (!mounted || !_foreground) return;
        await _player.play(DeviceFileSource(_audioFile!.path));
      } else {
        if (!mounted || !_foreground) return;
        await _player.play(UrlSource(resolved));
      }
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted)
        VitaNotice.error('experience.failed'.tr, 'moment.scene.audioFailed'.tr);
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    final sent = await _chat.send(text,
        experienceSpendId: _spend.isEmpty ? null : _spend);
    if (!mounted) return;
    if (sent)
      _input.clear();
    else
      VitaNotice.error('experience.failed'.tr,
          _chat.sendError.value ?? 'experience.failed'.tr);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioCompleted?.cancel();
    _player.dispose();
    if (_audioFile != null)
      unawaited(_audioFile!.delete().catchError((_) => _audioFile!));
    Get.delete<ChatController>(tag: _tag);
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.response['product'] as Map? ?? {};
    final reaction = _result['reaction_message'] as Map? ?? {};
    final initial =
        '${_result['reaction'] ?? reaction['content'] ?? _message['content'] ?? ''}';
    final voice = _message['message_type'] == 'voice';
    return Scaffold(
        backgroundColor: context.vita.pageBg,
        appBar: AppBar(
            leading: const VitaBackButton(),
            title: Text('experience.title'.tr)),
        body: Obx(() {
          final messages = _chat.messages.where((m) {
            final payload = m['payload'];
            return _spend.isNotEmpty &&
                payload is Map &&
                payload['shared_experience_spend_id'] == _spend;
          }).toList();
          final replies = _chat.messages
              .where((m) =>
                  m['sender_type'] == 'assistant' &&
                  m['payload'] is Map &&
                  (m['payload'] as Map)['shared_experience_spend_id'] == _spend)
              .toList();
          final reply = replies.lastOrNull;
          final user =
              messages.where((m) => m['sender_type'] == 'user').lastOrNull;
          final actions = sharedSceneActions(reply);
          final history = [...messages, ...replies]..sort(
              (a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
          return SharedExperienceStage(
            name: widget.name,
            portrait: widget.portrait,
            title: '${product['name_key'] ?? 'experience.title'}'.tr,
            reply: '${reply?['content'] ?? initial}',
            lastAction: '${user?['content'] ?? ''}',
            input: _input,
            busy: _chat.sending.value ||
                ['pending', 'processing', 'scheduled']
                    .contains(_chat.replyStatus.value),
            onSend: _send,
            actions: actions.isNotEmpty
                ? actions
                : user == null
                    ? [
                        {
                          'label': 'moment.choice.general.first'.tr,
                          'message': 'moment.choice.general.firstMessage'.tr
                        },
                        {
                          'label': 'moment.choice.general.second'.tr,
                          'message': 'moment.choice.general.secondMessage'.tr
                        },
                      ]
                    : [],
            attachment: _media.isEmpty
                ? null
                : voice
                    ? OutlinedButton.icon(
                        onPressed: _audioLoading ? null : _play,
                        icon: Icon(
                            _playing ? Icons.pause : Icons.play_arrow_outlined),
                        label: Text('moment.scene.listen'.tr),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48)))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                            height: 200,
                            child: VitaMediaImage(
                                url: _media,
                                errorBuilder: (_, __, ___) => Center(
                                    child: Text(
                                        'experience.flow.mediaInChat'.tr,
                                        style: const TextStyle(
                                            color: Colors.white)))))),
            onHistory: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                backgroundColor: context.vita.surface,
                builder: (_) => SizedBox(
                    height: MediaQuery.sizeOf(context).height * .65,
                    child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: history
                            .map((m) =>
                                ListTile(title: Text('${m['content'] ?? ''}')))
                            .toList()))),
          );
        }));
  }
}
