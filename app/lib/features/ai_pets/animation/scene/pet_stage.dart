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
/// 天气粒子 + 状态特效 + 宠物名称。整页（含标题）都随世界时钟动起来。
class PetStage extends StatelessWidget {
  const PetStage({
    super.key,
    required this.name,
    required this.imageUrl,
    this.spriteSheetUrl = '',
    this.actionSheetUrl = '',
    required this.machine,
    required this.clock,
    required this.weather,
    required this.onTap,
    required this.onLook,
    required this.onBack,
    this.speech,
  });

  final String name;
  final String imageUrl;
  final String spriteSheetUrl;
  final String actionSheetUrl;
  final PetStateMachine machine;
  final WorldClock clock;
  final Weather weather;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLook;
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
                child: LayoutBuilder(builder: (context, constraints) {
                  final size = math.min(constraints.maxWidth * .72, 280.0);
                  final availableTravel =
                      math.max(0.0, (constraints.maxWidth - size) / 2 - 12);
                  final walking = machine.weightFor(PetState.walking);
                  final travel = math.min(availableTravel, 62.0) *
                      walking *
                      math.sin(worldTime * math.pi * 2 * 10);
                  return Transform.translate(
                    offset: Offset(travel, 0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onTap,
                            onPanUpdate: (details) => onLook(Offset(
                              (details.localPosition.dx / size - .5) * 2,
                              (details.localPosition.dy / size - .5) * 2,
                            )),
                            onPanEnd: (_) => onLook(Offset.zero),
                            onPanCancel: () => onLook(Offset.zero),
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
                        ),
                        IgnorePointer(
                          child: PetFxLayer(
                            machine: machine,
                            worldTime: worldTime,
                            speech: speech,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
