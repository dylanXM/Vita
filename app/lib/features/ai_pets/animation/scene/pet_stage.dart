import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../house/pet_house.dart';
import '../pet/pet_expression.dart';
import '../pet/pet_motion_spec.dart';
import '../pet/pet_renderer.dart';
import '../pet/pet_state_machine.dart';
import '../ui/pet_title_bar.dart';
import '../world_clock.dart';
import 'background_layer.dart';
import 'sticker_layer.dart';
import 'weather_particles.dart';

/// 领养后整页动画舞台：全屏动态背景 + 贴纸层 + 宠物小屋 + 宠物 +
/// 天气粒子 + 状态特效 + 动画标题栏。整页（含标题）都随世界时钟动起来。
class PetStage extends StatelessWidget {
  const PetStage({
    super.key,
    required this.name,
    required this.species,
    required this.level,
    required this.imageUrl,
    required this.spriteSheetUrl,
    required this.actionSheetUrl,
    required this.machine,
    required this.clock,
    required this.weather,
    required this.onTap,
    required this.onBack,
    this.speech,
  });

  final String name;
  final String species;
  final int level;
  final String imageUrl;
  final String spriteSheetUrl;
  final String actionSheetUrl;
  final PetStateMachine machine;
  final WorldClock clock;
  final Weather weather;
  final VoidCallback onTap;
  final VoidCallback onBack;
  final String? speech;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Semantics(
      label: name,
      child: AnimatedBuilder(
        animation: Listenable.merge([clock, machine]),
        builder: (context, _) {
          final dayProgress = clock.dayProgress;
          final worldTime = clock.worldTime;
          final night = dayProgress < .2 || dayProgress > .8;
          final doorAmount = machine.weightFor(PetState.sleeping);
          final smokeOpacity = machine.weightFor(PetState.levelUp);
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. 动态天空/远山/草地背景。
              BackgroundLayer(
                dayProgress: dayProgress,
                worldTime: worldTime,
              ),
              // 2. 贴纸装饰层。
              StickerLayer(
                worldTime: worldTime,
                dayProgress: dayProgress,
                opacity: night ? .65 : 1,
              ),
              // 3. 宠物小屋（左下角）。
              Positioned(
                left: -18,
                bottom: 66,
                child: SizedBox(
                  width: 132,
                  height: 132,
                  child: PetHouse(
                    dayProgress: dayProgress,
                    worldTime: worldTime,
                    doorAmount: doorAmount,
                    lightOn: night,
                    smokeOpacity: smokeOpacity,
                  ),
                ),
              ),
              // 4. 宠物本体 + 状态特效（居中偏下，贴地站立）。
              Positioned(
                left: 0,
                right: 0,
                bottom: 56,
                height: 360,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final size =
                            math.min(constraints.maxWidth * .72, 280.0);
                        return Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onTap,
                            child: PetRenderer(
                              name: name,
                              imageUrl: imageUrl,
                              spriteSheetUrl: spriteSheetUrl,
                              actionSheetUrl: actionSheetUrl,
                              machine: machine,
                              worldTime: worldTime,
                              size: size,
                            ),
                          ),
                        );
                      },
                    ),
                    IgnorePointer(
                      child: PetFxLayer(
                        machine: machine,
                        worldTime: worldTime,
                        poseSheet: spriteSheetUrl.isNotEmpty,
                        speech: speech,
                      ),
                    ),
                  ],
                ),
              ),
              // 5. 天气粒子。
              Positioned.fill(
                child: IgnorePointer(
                  child: WeatherParticles(
                    weather: weather,
                    worldTime: worldTime,
                  ),
                ),
              ),
              // 6. 动画标题栏（顶部）。
              Positioned(
                left: 16,
                right: 16,
                top: safeTop + 10,
                child: PetTitleBar(
                  name: name,
                  level: level,
                  species: species,
                  machine: machine,
                  clock: clock,
                  onBack: onBack,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
