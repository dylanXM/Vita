import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/media_image.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

/// Edit the signed-in user's display name and avatar. Reached from Settings →
/// Account → Profile. Follows the flat WeChat-style grouped list used across
/// the app: light-gray canvas, white surfaces, hairline separators, 17 px
/// centered navigation title.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _nicknameController = TextEditingController();
  bool _initialized = false;

  /// Current avatar URL. Null means "keep the existing one"; a value means the
  /// user picked a new image (either already uploaded or pending upload).
  String? _avatarUrl;

  /// True while a new avatar is being picked / uploaded.
  bool _uploadingAvatar = false;

  /// True while the save request is in flight.
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _nicknameController.text = AuthController.to.nickname;
      _avatarUrl = AuthController.to.avatarUrl;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    final XFile? image;
    try {
      image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
      );
    } catch (_) {
      if (!mounted) return;
      Get.snackbar('profile.avatar'.tr, 'profile.pickFailed'.tr);
      return;
    }
    if (image == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final result = await ApiClient.instance
          .upload('/v1/media/upload', image.path, kind: 'image');
      final map = Map<String, dynamic>.from(result as Map);
      final url = map['url'] as String? ?? '';
      if (url.isEmpty) throw ApiException('upload returned no url');
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (e) {
      if (!mounted) return;
      Get.snackbar('profile.avatar'.tr,
          e is ApiException ? e.message : 'profile.uploadFailed'.tr);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final nickname = _nicknameController.text.trim();
    if (nickname.runes.length > 30) {
      Get.snackbar('profile.nickname'.tr, 'profile.nicknameTooLong'.tr);
      return;
    }
    setState(() => _saving = true);
    try {
      await AuthController.to.updateProfile(
        nickname: nickname,
        avatarUrl: _avatarUrl ?? '',
      );
      if (!mounted) return;
      Get.back();
    } catch (e) {
      if (!mounted) return;
      Get.snackbar('profile.saveFailed'.tr,
          e is ApiException ? e.message : 'profile.saveFailed'.tr);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final existingAvatar = AuthController.to.avatarUrl;

    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(
        title: Text('profile.edit.title'.tr),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(vita.green),
                    ),
                  )
                : Text('common.save'.tr),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          // Avatar picker — large centered circle, tap to replace.
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: GestureDetector(
                onTap: _pickAvatar,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _AvatarCircle(
                      url: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                          ? _avatarUrl!
                          : existingAvatar,
                      radius: 56,
                    ),
                    if (_uploadingAvatar)
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Nickname field, in the same flat grouped surface as other settings.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('profile.nickname'.tr, style: vita.sectionTitle),
          ),
          const SizedBox(height: 12),
          VitaCard(
            radius: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            margin: EdgeInsets.zero,
            child: TextField(
              controller: _nicknameController,
              maxLength: 30,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                counterText: '',
                hintText: 'profile.nickname.hint'.tr,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
              style: TextStyle(fontSize: 16, color: vita.text),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'profile.nickname.help'.tr,
              style: vita.sub,
            ),
          ),
        ],
      ),
    );
  }
}

/// Round avatar used on the edit page. Falls back to the first letter of the
/// email when no image is set, matching [VitaAvatar]'s fallback behavior.
class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.url, this.radius = 48});

  final String url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final source = url.trim();
    if (source.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: VitaMediaImage(url: source),
        ),
      );
    }
    final email = AuthController.to.email;
    final initial = email.isEmpty ? '?' : email[0].toUpperCase();
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: vita.greenTint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: vita.green,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
