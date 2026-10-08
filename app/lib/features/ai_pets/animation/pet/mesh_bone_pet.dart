import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'pet_motion_spec.dart';
import 'pet_state_machine.dart';

/// 网格形变骨骼姿态：全部为归一化参数（位移以图宽/高比例计，角度为弧度）。
/// 状态切换时对「旧姿态 → 新姿态」逐参数插值，保证形变连贯。
class MeshPose {
  const MeshPose({
    this.headDx = 0,
    this.headDy = 0,
    this.headRot = 0,
    this.bodyLean = 0,
    this.bodyBend = 0,
    this.bodyDy = 0,
    this.legSquash = 0,
    this.swingAmt = 0,
    this.squashAll = 0,
    this.tailSwing = 0,
  });

  /// 头部平移（图宽/图高比例）。
  final double headDx;
  final double headDy;

  /// 头部绕颈点旋转（弧度）。
  final double headRot;

  /// 躯干前倾（绕臀点，正 = 前倾，负 = 后仰）。
  final double bodyLean;

  /// 躯干弓起（中段水平凸起）。
  final double bodyBend;

  /// 整体垂直位移（呼吸 / 弹跳）。
  final double bodyDy;

  /// 腿部垂直压缩（0 = 不压缩，1 = 完全收起）。
  final double legSquash;

  /// 腿部左右交替摆动幅度。
  final double swingAmt;

  /// 整体向地面压扁（睡觉 / 趴下）。
  final double squashAll;

  /// 尾巴摆动幅度。
  final double tailSwing;

  MeshPose lerp(MeshPose other, double t) => MeshPose(
        headDx: headDx + (other.headDx - headDx) * t,
        headDy: headDy + (other.headDy - headDy) * t,
        headRot: headRot + (other.headRot - headRot) * t,
        bodyLean: bodyLean + (other.bodyLean - bodyLean) * t,
        bodyBend: bodyBend + (other.bodyBend - bodyBend) * t,
        bodyDy: bodyDy + (other.bodyDy - bodyDy) * t,
        legSquash: legSquash + (other.legSquash - legSquash) * t,
        swingAmt: swingAmt + (other.swingAmt - swingAmt) * t,
        squashAll: squashAll + (other.squashAll - squashAll) * t,
        tailSwing: tailSwing + (other.tailSwing - tailSwing) * t,
      );
}

/// 每个状态的基础姿态（与状态机的 spec 分离，专门描述「形变」而非位移）。
const Map<PetState, MeshPose> kMeshPoseTable = {
  PetState.standing: MeshPose(tailSwing: .03),
  PetState.idle: MeshPose(tailSwing: .03),
  // 坐下：身体后坐下沉、腿收拢压扁、头微抬。
  PetState.sitting: MeshPose(
    headDy: .05,
    headRot: .09,
    bodyLean: -.09,
    bodyDy: .10,
    legSquash: .5,
    squashAll: .08,
    tailSwing: .05,
  ),
  // 散步：身体前倾、腿交替摆动、头轻晃。
  PetState.walking: MeshPose(
    bodyLean: .035,
    swingAmt: .055,
    headRot: .035,
    tailSwing: .06,
  ),
  // 进食：低头探食、前倾。
  PetState.feeding: MeshPose(
    headDx: .06,
    headDy: .05,
    bodyLean: .06,
    bodyDy: .04,
    tailSwing: .04,
  ),
  // 开心：仰头挺胸，弹跳由相位驱动。
  PetState.happy: MeshPose(headDy: -.03, headRot: -.08, tailSwing: .08),
  // 睡觉：整体压向地面、头垂入身、腿完全收拢。
  PetState.sleeping: MeshPose(
    headDy: .26,
    bodyLean: .06,
    bodyDy: .14,
    legSquash: .68,
    squashAll: .3,
    tailSwing: .02,
  ),
  PetState.levelUp: MeshPose(headDy: -.04, headRot: -.06, tailSwing: .1),
  // 思考：歪头。
  PetState.thinking: MeshPose(headDy: -.02, headRot: .14, tailSwing: .04),
  // 困：头沉沉下垂、身体微弓。
  PetState.tired: MeshPose(
    headDy: .15,
    headRot: .16,
    bodyBend: .05,
    bodyDy: .05,
    legSquash: .16,
    tailSwing: .01,
  ),
  // 饿：头前伸下探、身体前倾。
  PetState.hungry: MeshPose(
    headDx: .12,
    headDy: .08,
    bodyLean: .06,
    bodyDy: .04,
    tailSwing: .01,
  ),
  // 生病：萎靡下垂。
  PetState.sick: MeshPose(
    headDy: .08,
    headRot: .1,
    bodyBend: -.03,
    bodyDy: .08,
    legSquash: .14,
    tailSwing: .01,
  ),
};

/// 归一化网格参数。
const int kMeshRows = 9; // v 方向控制点
const int kMeshCols = 7; // u 方向控制点

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 基于任意宠物图的网格形变骨骼动画渲染器。
///
/// 原理：把整张图铺成 (rows×cols) 控制点网格，按垂直分区把网格顶点绑定到
/// 头 / 躯干 / 腿 / 尾巴骨骼；每帧根据状态计算出顶点位移场，再把每个网格
/// 四边形拆成两个三角形，用「clip + 仿射变换 + drawImage」做三角形 warp，
/// 因此整张图 1:1 保留（形象零重绘），但能真实地低头、弓背、收腿、摆尾。
class MeshBonePet extends StatefulWidget {
  const MeshBonePet({
    super.key,
    required this.imageProvider,
    this.closedEyeProvider,
    required this.machine,
    required this.worldTime,
  });

  final ImageProvider imageProvider;
  final ImageProvider? closedEyeProvider;
  final PetStateMachine machine;
  final double worldTime;

  @override
  State<MeshBonePet> createState() => _MeshBonePetState();
}

class _MeshBonePetState extends State<MeshBonePet> {
  ui.Image? _image;
  ui.Image? _closedEye;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MeshBonePet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider ||
        oldWidget.closedEyeProvider != widget.closedEyeProvider) {
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    _image = null;
    _closedEye = null;
    if (mounted) setState(() {});
    try {
      final img = await _resolve(widget.imageProvider);
      ui.Image? close;
      if (widget.closedEyeProvider != null) {
        close = await _resolve(widget.closedEyeProvider!);
      }
      if (!mounted) return;
      setState(() {
        _image = img;
        _closedEye = close;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<ui.Image> _resolve(ImageProvider provider) {
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  double _blinkAmount(double worldTime) {
    final progress = (worldTime * 14.28) % 1.0;
    if (progress < .86 || progress > .96) return 0;
    if (progress < .91) return (progress - .86) / .05;
    return 1 - ((progress - .91) / .05);
  }

  /// 计算某状态在给定相位下的基础形变姿态。
  MeshPose _poseFor(PetState state, double cycle, double worldTime) {
    final base = kMeshPoseTable[state] ?? kMeshPoseTable[PetState.standing]!;
    // 呼吸：约 2.6 秒一个周期。
    final idle = math.sin(worldTime * math.pi * 2 * 23);
    final actionWave = math.sin(cycle * math.pi);
    final repeatingWave = math.sin(cycle * math.pi * 2);

    double bodyDy = base.bodyDy;
    double headRot = base.headRot;
    double swing = base.swingAmt;

    switch (state) {
      case PetState.standing:
      case PetState.idle:
        bodyDy += idle * .006;
        break;
      case PetState.walking:
        bodyDy += repeatingWave.abs() * .012;
        headRot += repeatingWave * .02;
        break;
      case PetState.happy:
        bodyDy -= actionWave.abs() * .09;
        headRot += actionWave * .04;
        break;
      case PetState.feeding:
        bodyDy += repeatingWave.abs() * .02;
        break;
      case PetState.sleeping:
        bodyDy += idle * .005;
        break;
      case PetState.levelUp:
        bodyDy -= actionWave.abs() * .07;
        break;
      case PetState.sitting:
      case PetState.tired:
      case PetState.hungry:
      case PetState.thinking:
      case PetState.sick:
        bodyDy += idle * .004;
        break;
    }
    return MeshPose(
      headDx: base.headDx,
      headDy: base.headDy,
      headRot: headRot + idle * .02,
      bodyLean: base.bodyLean,
      bodyBend: base.bodyBend,
      bodyDy: bodyDy,
      legSquash: base.legSquash,
      swingAmt: swing,
      squashAll: base.squashAll,
      tailSwing: base.tailSwing + (state == PetState.standing ||
              state == PetState.idle
          ? .03 * math.sin(worldTime * math.pi * 4)
          : 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return _failed
          ? const SizedBox.shrink()
          : Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF9B7CFF), width: 2.5),
                  ),
                ),
              ),
            );
    }
    final state = widget.machine.state;
    final cycle = widget.machine.controller.value;
    final phase = cycle * math.pi * 2;
    final from = _poseFor(widget.machine.previous, cycle, widget.worldTime);
    final to = _poseFor(state, cycle, widget.worldTime);
    final pose = from.lerp(to, widget.machine.blendValue);
    final blink = state == PetState.sleeping
        ? 1.0
        : state == PetState.feeding
            ? 0.0
            : _blinkAmount(widget.worldTime);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 300.0;
        final ch = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 300.0;
        return CustomPaint(
          size: Size(cw, ch),
          painter: _MeshPainter(
            image: image,
            closedEye: _closedEye,
            blink: blink,
            pose: pose,
            phase: phase,
            width: cw,
            height: ch,
          ),
        );
      },
    );
  }
}

/// 网格顶点 (u, v) 在当前姿态下的位移（归一化，乘图尺寸得像素）。
Offset offsetAt(MeshPose pose, double u, double v, double phase) {
  double dx = 0, dy = 0;

  // ---- 头带：绕颈点 (0.5, 0.34) 旋转 + 平移 ----
  final headW = 1 - _smoothstep(.30, .50, v);
  if (headW > 0) {
    final vv = (v - .34) * headW;
    final uu = (u - .5) * headW;
    final ca = math.cos(pose.headRot);
    final sa = math.sin(pose.headRot);
    dx += headW * ((uu * ca - vv * sa - uu) + pose.headDx);
    dy += headW * ((uu * sa + vv * ca - vv) + pose.headDy);
  }

  // ---- 躯干带：前倾 / 弓起 / 呼吸 ----
  final bodyW = (1 - _smoothstep(.40, .54, v)) * _smoothstep(.66, .80, v);
  if (bodyW > 0) {
    dx += bodyW * (pose.bodyLean * (.72 - v) +
        pose.bodyBend * math.sin((v - .40) / (.72 - .40) * math.pi));
    dy += bodyW * pose.bodyDy;
  }

  // ---- 整体压扁（v 中下部向地面收）----
  final squashW = _smoothstep(.25, .38, v);
  dy += squashW * pose.squashAll * (.72 - v);

  // ---- 腿带：压缩 + 左右交替摆动 ----
  final legW = _smoothstep(.72, .84, v);
  if (legW > 0) {
    dy -= legW * pose.legSquash * (v - .72);
    final side = u < .5 ? -1.0 : 1.0;
    final swingW = _smoothstep(.76, .92, v);
    dy += legW * swingW * pose.swingAmt * side * math.sin(phase);
  }

  // ---- 尾巴：侧向摆动 ----
  final tailW = _smoothstep(.60, .74, u) *
      (1 - _smoothstep(.28, .44, v)) *
      _smoothstep(.58, .70, v);
  if (tailW > 0) {
    dx += tailW * pose.tailSwing * math.sin(phase * 2) * (u - .55) * 3;
    dy += tailW * pose.tailSwing * math.cos(phase * 2) * .06;
  }

  return Offset(dx, dy);
}

/// 三角形 warp 绘制器：整图网格化后逐三角形 clip + 仿射绘制。
class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.image,
    required this.closedEye,
    required this.blink,
    required this.pose,
    required this.phase,
    required this.width,
    required this.height,
  });

  final ui.Image image;
  final ui.Image? closedEye;
  final double blink;
  final MeshPose pose;
  final double phase;
  final double width;
  final double height;

  static final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    // contain 适配：整图等比放入画布并居中。
    final scale = math.min(width / iw, height / ih);
    final ox = (width - iw * scale) / 2;
    final oy = (height - ih * scale) / 2;

    // 源网格顶点（图像像素坐标）与目标网格顶点（画布坐标）。
    final src = List.generate(
      kMeshRows * kMeshCols,
      (i) => Offset(
        (i % kMeshCols) / (kMeshCols - 1) * iw,
        (i ~/ kMeshCols) / (kMeshRows - 1) * ih,
      ),
      growable: false,
    );
    final dst = List<Offset>.filled(kMeshRows * kMeshCols, Offset.zero);
    for (var r = 0; r < kMeshRows; r++) {
      for (var c = 0; c < kMeshCols; c++) {
        final u = c / (kMeshCols - 1);
        final v = r / (kMeshRows - 1);
        final off = offsetAt(pose, u, v, phase);
        dst[r * kMeshCols + c] = Offset(
          ox + u * iw * scale + off.dx * iw * scale,
          oy + v * ih * scale + off.dy * ih * scale,
        );
      }
    }

    for (var r = 0; r < kMeshRows - 1; r++) {
      for (var c = 0; c < kMeshCols - 1; c++) {
        final i0 = r * kMeshCols + c;
        final i1 = i0 + 1;
        final i2 = (r + 1) * kMeshCols + c;
        final i3 = i2 + 1;
        _drawTri(canvas, src[i0], src[i1], src[i2], dst[i0], dst[i1], dst[i2]);
        _drawTri(canvas, src[i1], src[i3], src[i2], dst[i1], dst[i3], dst[i2]);
      }
    }
  }

  void _drawTri(
    Canvas canvas,
    Offset s0,
    Offset s1,
    Offset s2,
    Offset d0,
    Offset d1,
    Offset d2,
  ) {
    // 闭合三角形路径（向外扩张 0.5px，消除相邻三角形间的细缝）。
    final centroid = Offset((d0.dx + d1.dx + d2.dx) / 3, (d0.dy + d1.dy + d2.dy) / 3);
    Offset grow(Offset p) {
      final d = p - centroid;
      final len = math.sqrt(d.dx * d.dx + d.dy * d.dy);
      if (len < 1e-6) return p;
      final k = 0.5 / len;
      return Offset(p.dx + d.dx * k, p.dy + d.dy * k);
    }

    final g0 = grow(d0), g1 = grow(d1), g2 = grow(d2);
    final path = Path()
      ..moveTo(g0.dx, g0.dy)
      ..lineTo(g1.dx, g1.dy)
      ..lineTo(g2.dx, g2.dy)
      ..close();

    // 仿射变换：源三角形 → 目标三角形。
    final m = _affine(s0, s1, s2, d0, d1, d2);

    canvas.save();
    canvas.clipPath(path);
    canvas.transform(m);
    canvas.drawImage(image, Offset.zero, _paint);
    if (closedEye != null && blink > 0) {
      _paint.color = const Color.fromARGB(255, 255, 255, 255)
          .withValues(alpha: blink.clamp(0.0, 1.0));
      canvas.drawImage(closedEye!, Offset.zero, _paint);
      _paint.color = const Color.fromRGBO(255, 255, 255, 1);
    }
    canvas.restore();
  }

  /// 由三点对计算 2D 仿射矩阵（src → dst）。
  Float64List _affine(Offset p0, Offset p1, Offset p2, Offset q0, Offset q1,
      Offset q2) {
    final ux = p1.dx - p0.dx, uy = p1.dy - p0.dy;
    final vx = p2.dx - p0.dx, vy = p2.dy - p0.dy;
    final det = ux * vy - uy * vx;
    if (det.abs() < 1e-9) {
      return Matrix4.identity().storage;
    }
    final uqx = q1.dx - q0.dx, uqy = q1.dy - q0.dy;
    final vqx = q2.dx - q0.dx, vqy = q2.dy - q0.dy;
    final a = (uqx * vy - vqx * uy) / det;
    final b = (vqx * ux - uqx * vx) / det;
    final c = (uqy * vy - vqy * uy) / det;
    final d = (vqy * ux - uqy * vx) / det;
    final tx = q0.dx - a * p0.dx - b * p0.dy;
    final ty = q0.dy - c * p0.dx - d * p0.dy;
    // Matrix4 参数为行主序：[[a,b,0,tx],[c,d,0,ty],[0,0,1,0],[0,0,0,1]]
    return Matrix4(a, b, 0, tx, c, d, 0, ty, 0, 0, 1, 0, 0, 0, 0, 1).storage;
  }

  @override
  bool shouldRepaint(_MeshPainter oldDelegate) => true;
}
