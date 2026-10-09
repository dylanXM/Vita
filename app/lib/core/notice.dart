import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'theme.dart';

enum _NoticeKind { success, error, warning, info }

/// Short, typed feedback for user actions. Chat and system messages use their
/// own surfaces; they must not be presented as action feedback.
class VitaNotice {
  const VitaNotice._();

  static void success(String title, String message) =>
      _show(_NoticeKind.success, title, message);

  static void error(String title, String message) =>
      _show(_NoticeKind.error, title, message);

  static void warning(String title, String message) =>
      _show(_NoticeKind.warning, title, message);

  static void info(String title, String message) =>
      _show(_NoticeKind.info, title, message);

  static void _show(_NoticeKind kind, String title, String message) {
    final context = Get.context;
    final vita = context?.vita;
    final color = switch (kind) {
      _NoticeKind.success => vita?.green ?? const Color(0xFF168351),
      _NoticeKind.error => vita?.red ?? const Color(0xFFD83A45),
      _NoticeKind.warning => const Color(0xFFB87510),
      _NoticeKind.info => const Color(0xFF3775B8),
    };
    final icon = switch (kind) {
      _NoticeKind.success => Icons.check_circle_outline_rounded,
      _NoticeKind.error => Icons.error_outline_rounded,
      _NoticeKind.warning => Icons.warning_amber_rounded,
      _NoticeKind.info => Icons.info_outline_rounded,
    };
    final label = switch (kind) {
      _NoticeKind.success => 'notice.success'.tr,
      _NoticeKind.error => 'notice.error'.tr,
      _NoticeKind.warning => 'notice.warning'.tr,
      _NoticeKind.info => 'notice.info'.tr,
    };
    Get.snackbar(
      '$label · $title',
      message,
      snackPosition: SnackPosition.TOP,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      maxWidth: 440,
      borderRadius: 12,
      borderColor: color.withValues(alpha: 0.35),
      borderWidth: 1,
      leftBarIndicatorColor: color,
      backgroundColor: vita?.surface ?? const Color(0xFF222327),
      colorText: vita?.text ?? Colors.white,
      icon: Icon(icon, color: color, size: 22, semanticLabel: label),
      shouldIconPulse: false,
      duration: Duration(seconds: kind == _NoticeKind.error ? 5 : 3),
      isDismissible: true,
    );
  }
}
