import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/legal_documents.dart';
import '../../core/theme.dart';
import '../settings/legal_document_page.dart';

class RegistrationLegalConsent extends StatelessWidget {
  const RegistrationLegalConsent({
    required this.accepted,
    required this.onChanged,
    super.key,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;

  void _open(LegalDocumentType type) {
    Get.to(
      () => LegalDocumentPage(type: type),
      transition: Transition.cupertino,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final normal = TextStyle(color: vita.subText, fontSize: 12.5, height: 1.45);
    final link = normal.copyWith(color: vita.green);

    return Semantics(
      label: 'auth.legalConsent'.tr,
      checked: accepted,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            height: 44,
            child: Checkbox(
              key: const ValueKey('registration-legal-checkbox'),
              value: accepted,
              onChanged: (value) => onChanged(value ?? false),
              activeColor: vita.green,
              checkColor: Colors.white,
              shape: const CircleBorder(),
              side: BorderSide(color: vita.hint, width: 1),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('auth.legalPrefix'.tr, style: normal),
                  InkWell(
                    key: const ValueKey('open-terms'),
                    onTap: () => _open(LegalDocumentType.terms),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('settings.terms'.tr, style: link),
                    ),
                  ),
                  Text('auth.legalAnd'.tr, style: normal),
                  InkWell(
                    key: const ValueKey('open-privacy'),
                    onTap: () => _open(LegalDocumentType.privacy),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('settings.privacy'.tr, style: link),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
