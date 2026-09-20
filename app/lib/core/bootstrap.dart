import 'package:get/get.dart';

import 'settings_controller.dart';
import 'app_content_controller.dart';
import 'analytics_service.dart';
import '../features/auth/auth_controller.dart';
import '../features/billing/billing_controller.dart';
import '../features/chat/chat_list_controller.dart';
import '../features/life/life_page.dart';
import '../features/explore/explore_page.dart';
import '../features/memories/memories_page.dart';
import '../features/shell/shell_page.dart';

/// Registers the app-wide controllers. Called by main() and by the widget
/// tests so both exercise the same wiring.
void initControllers() {
  Get.put(VitaSettingsController(), permanent: true);
  Get.put(AnalyticsService(), permanent: true);
  Get.put(AppContentController(), permanent: true);
  Get.put(AuthController(), permanent: true);
  Get.put(ChatListController(), permanent: true);
  Get.put(LifeController(), permanent: true);
  Get.put(MemoriesController(), permanent: true);
  Get.put(ExploreController(), permanent: true);
  Get.put(ShellController(), permanent: true);
  Get.put(BillingController(), permanent: true);
}
