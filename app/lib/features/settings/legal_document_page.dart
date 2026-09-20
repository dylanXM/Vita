import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/legal_documents.dart';
import '../../core/theme.dart';

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.type, super.key});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final locale = Get.locale ?? Localizations.localeOf(context);
    final document = legalDocumentFor(locale, type);
    final title = type == LegalDocumentType.privacy
        ? 'settings.privacy'.tr
        : 'settings.terms'.tr;

    return Scaffold(
      backgroundColor: vita.pageBg,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              title,
              style: TextStyle(
                color: vita.text,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              document.updatedLabel,
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
        ),
      ),
    );
  }
}
