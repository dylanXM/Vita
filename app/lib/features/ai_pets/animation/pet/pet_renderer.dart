import 'package:flutter/material.dart';

import '../../ai_pet_avatar.dart';
import 'pet_pose_sheet.dart';
import 'pet_state_machine.dart';

/// Flame renders authored poses and action frames when available. Pets without
/// sheets keep their original portrait instead of receiving a distorted pose.
class PetRenderer extends StatelessWidget {
  const PetRenderer({
    super.key,
    required this.name,
    required this.imageUrl,
    this.spriteSheetUrl = '',
    this.actionSheetUrl = '',
    required this.machine,
    required this.worldTime,
    this.size = 260,
  });

  final String name;
  final String imageUrl;
  final String spriteSheetUrl;
  final String actionSheetUrl;
  final PetStateMachine machine;
  final double worldTime;
  final double size;

  @override
  Widget build(BuildContext context) {
    final sheet = spriteSheetUrl.isNotEmpty
        ? spriteSheetUrl
        : (aiPetPoseSheetAssetPath(imageUrl) == null
            ? ''
            : 'asset://${aiPetPoseSheetAssetPath(imageUrl)}');
    final actions = actionSheetUrl.isNotEmpty
        ? actionSheetUrl
        : (aiPetActionSheetAssetPath(imageUrl) == null
            ? ''
            : 'asset://${aiPetActionSheetAssetPath(imageUrl)}');
    return SizedBox(
      width: size,
      height: size,
      child: sheet.isEmpty
          ? AIPetAvatar(name: name, imageUrl: imageUrl)
          : RepaintBoundary(
              child: PetPoseSheet(
                name: name,
                avatarUrl: imageUrl,
                sheetUrl: sheet,
                actionSheetUrl: actions,
                machine: machine,
              ),
            ),
    );
  }
}
