import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/legal_documents.dart';
import '../../core/app_content_controller.dart';
import '../../core/theme.dart';

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.type, super.key});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final title = type == LegalDocumentType.privacy
        ? 'settings.privacy'.tr
        : 'settings.terms'.tr;

    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
          top: false,
          child: Obx(() {
            final document = AppContentController.to.legalDocument(type);
            if (document == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('legal.unavailable'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: vita.subText)),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: AppContentController.to.load,
                      child: Text('common.retry'.tr),
                    ),
                  ]),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  document.title,
                  style: TextStyle(
                    color: vita.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'legal.updatedAt'.trParams({
                    'time': _formatUpdatedAt(document.updatedAt),
                    'version': document.version,
                  }),
                  style: TextStyle(color: vita.subText, fontSize: 12.5),
                ),
                const SizedBox(height: 18),
                Text(
                  document.summary,
                  style: TextStyle(
                    color: vita.text,
                    fontSize: 15,
                    height: 1.65,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                SelectableText(
                  document.body,
                  style: TextStyle(color: vita.text, fontSize: 14, height: 1.7),
                ),
              ],
            );
          })),
    );
  }

  String _formatUpdatedAt(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}
