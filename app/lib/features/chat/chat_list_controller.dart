import 'package:get/get.dart';

import '../../core/api_client.dart';

/// Loads the user's companions for the Chat tab.
class ChatListController extends GetxController {
  static ChatListController get to => Get.find();

  final loading = false.obs;
  final companions = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    try {
      final data = await ApiClient.instance.get('/v1/companions');
      if (data is List) {
        companions.assignAll(
          data.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)),
        );
      }
    } catch (_) {
      // keep the previous list; the empty state explains itself
    } finally {
      loading.value = false;
    }
  }
}
