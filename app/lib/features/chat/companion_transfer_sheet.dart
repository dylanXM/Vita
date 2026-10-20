import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/notice.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../billing/billing_controller.dart';

class CompanionTransferSheet extends StatefulWidget {
  const CompanionTransferSheet(
      {super.key,
      required this.companionId,
      required this.companionName,
      required this.onCompleted});

  final String companionId;
  final String companionName;
  final Future<void> Function() onCompleted;

  @override
  State<CompanionTransferSheet> createState() => _CompanionTransferSheetState();
}

class _CompanionTransferSheetState extends State<CompanionTransferSheet> {
  int _amount = 10;
  bool _busy = false;
  String? _requestKey;

  Future<void> _transfer() async {
    if (_busy) return;
    _requestKey ??=
        '${widget.companionId}-${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _busy = true);
    try {
      await ApiClient.instance.post(
          '/v1/companions/${widget.companionId}/transfers',
          data: {'coins': _amount, 'request_key': _requestKey});
      await BillingController.to.refreshCredits();
      await widget.onCompleted();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'insufficient_credits') {
        Navigator.of(context).pop();
        Get.toNamed('/credits');
      } else {
        VitaNotice.error('chat.transfer'.tr, error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vita = context.vita;
    final balance = BillingController.to.balance.value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('chat.transfer'.tr,
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: vita.text)),
              const SizedBox(height: 10),
              Text(
                  'transfer.description'
                      .trParams({'name': widget.companionName}),
                  style: TextStyle(
                      fontSize: 14, height: 1.45, color: vita.subText)),
              const SizedBox(height: 20),
              Text('experience.balance'.trParams({'coins': '$balance'}),
                  style: TextStyle(color: vita.subText, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                  children: [10, 30, 100].map((amount) {
                final selected = _amount == amount;
                return Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _amount = amount;
                              _requestKey = null;
                            }),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected ? vita.greenTint : vita.surface,
                      side: BorderSide(
                          color: selected ? vita.green : vita.divider),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: Text('$amount',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: selected ? vita.green : vita.text)),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _transfer,
                    child: Text(
                        _busy ? 'transfer.sending'.tr : 'transfer.confirm'.tr),
                  )),
            ]),
      ),
    );
  }
}
