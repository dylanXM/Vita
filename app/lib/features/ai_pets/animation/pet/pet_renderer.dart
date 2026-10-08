import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ai_pet_avatar.dart';
import 'mesh_bone_pet.dart';
import 'pet_motion_spec.dart';
import 'pet_state_machine.dart';

/// 宠物本体渲染：由状态机 + 世界时钟驱动「网格形变骨骼动画」。
///
/// 任意宠物图（网络 / 本地 / 上传文件）都会被铺成网格并按骨骼分区绑定，
/// 状态切换时姿态逐参数插值，宠物像真的在生活（低头、弓背、收腿、摆尾），
/// 形象始终 1:1 来自原图。纯表现层，不感知 AI 来源。
class PetRenderer extends StatelessWidget {
  const PetRenderer({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.machine,
    required this.worldTime,
  });

  final String name;
  final String imageUrl;
  final PetStateMachine machine;
  final double worldTime;

  ImageProvider _provider(String url) {
    if (url.startsWith('asset://')) {
      return AssetImage(url.substring('asset://'.length));
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return NetworkImage(url);
    }
    throw ArgumentError.value(url, 'url', 'Unsupported pet image URL');
  }

  @override
  Widget build(BuildContext context) {
    if (!imageUrl.startsWith('asset://') &&
        !imageUrl.startsWith('http://') &&
        !imageUrl.startsWith('https://')) {
      return const SizedBox(
        width: 340,
        height: 340,
        child: Icon(Icons.pets_rounded, size: 120),
      );
    }
    final blinkPath = aiPetClosedEyeAssetPath(imageUrl);
    final walkingWeight = machine.weightFor(PetState.walking);
    final walkingDistance = PetMotionSpec.table[PetState.walking]!.driftX;
    final walkX = walkingWeight *
        walkingDistance *
        .5 *
        math.sin(worldTime * math.pi * 2 * 10);
    var scale = 0.0;
    for (final entry in machine.stateWeights.entries) {
      scale += PetMotionSpec.table[entry.key]!.scale * entry.value;
    }
    return SizedBox(
      width: 340,
      height: 340,
      child: Transform.translate(
        offset: Offset(walkX, 0),
        child: Transform.scale(
          alignment: Alignment.bottomCenter,
          scale: scale,
          child: MeshBonePet(
            imageProvider: _provider(imageUrl),
            closedEyeProvider: blinkPath == null ? null : AssetImage(blinkPath),
            machine: machine,
            worldTime: worldTime,
          ),
        ),
      ),
    );
  }
}
