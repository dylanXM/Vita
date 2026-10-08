import 'package:flutter/material.dart';

import '../../ai_pet_avatar.dart';
import 'pet_pose_sheet.dart';
import 'pet_state_machine.dart';

/// Full-body authored poses replace the generic whole-image mesh deformation.
/// A legacy pet without a sheet keeps its original portrait intact.
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
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: spriteSheetUrl.isEmpty
            ? AIPetAvatar(name: name, imageUrl: imageUrl)
            : PetPoseSheet(
                name: name,
                avatarUrl: imageUrl,
                sheetUrl: spriteSheetUrl,
                actionSheetUrl: actionSheetUrl,
                machine: machine,
                worldTime: worldTime,
              ),
      );
}
