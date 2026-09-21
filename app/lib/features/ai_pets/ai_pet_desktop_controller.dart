import 'package:get/get.dart';

import '../../core/api_client.dart';
import '../../core/settings_controller.dart';
import '../auth/auth_controller.dart';

class AIPetDesktopController extends GetxController {
  static AIPetDesktopController get to => Get.find();

  final pet = Rxn<Map<String, dynamic>>();
  Worker? _settingsWorker;
  Worker? _profileWorker;
  int _requestGeneration = 0;

  @override
  void onInit() {
    super.onInit();
    _settingsWorker = ever<bool>(
      VitaSettingsController.to.petDesktopEnabled,
      (_) => refreshPet(),
    );
    _profileWorker = ever<Map<String, dynamic>?>(
      AuthController.to.profile,
      (_) => refreshPet(),
    );
    refreshPet();
  }

  Future<void> refreshPet() async {
    final generation = ++_requestGeneration;
    if (!VitaSettingsController.to.petDesktopEnabled.value ||
        AuthController.to.profile.value == null) {
      pet.value = null;
      return;
    }
    try {
      final data = await ApiClient.instance.get('/v1/ai-pets/breeds');
      if (generation != _requestGeneration) return;
      final items = data is Map ? data['items'] : null;
      Map<dynamic, dynamic>? adopted;
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          if ('${item['adopted_companion_id'] ?? ''}'.isNotEmpty) {
            adopted = item;
            break;
          }
        }
      }
      pet.value = adopted == null ? null : Map<String, dynamic>.from(adopted);
    } catch (_) {
      if (generation == _requestGeneration) pet.value = null;
    }
  }

  @override
  void onClose() {
    _settingsWorker?.dispose();
    _profileWorker?.dispose();
    super.onClose();
  }
}
