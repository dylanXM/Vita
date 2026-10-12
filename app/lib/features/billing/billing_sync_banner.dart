import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'billing_controller.dart';

class BillingSyncBanner extends StatelessWidget {
  const BillingSyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BillingController.to;
    return Obx(() => !controller.fulfillmentPending.value
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: VitaCard(
              margin: EdgeInsets.zero,
              child: SizedBox(
                height: 64,
                child: Row(children: [
                  Icon(Icons.sync_rounded, color: context.vita.green),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('billing.fulfillmentPending'.tr,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.vita.text))),
                  IconButton(
                    tooltip: 'billing.retrySync'.tr,
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: controller.checkingFulfillment.value
                        ? null
                        : () async {
                            await controller.syncUser(controller.currentUserID);
                            await controller.retryPendingPurchases();
                          },
                  ),
                ]),
              ),
            ),
          ));
  }
}
