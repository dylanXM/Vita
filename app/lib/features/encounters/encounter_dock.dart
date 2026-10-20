import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class EncounterDock extends StatefulWidget {
  const EncounterDock({super.key, required this.index, required this.onTab,
    required this.onCreate});
  final int index;
  final ValueChanged<int> onTab;
  final Future<void> Function() onCreate;
  @override State<EncounterDock> createState() => _EncounterDockState();
}

class _EncounterDockState extends State<EncounterDock>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _glow;
  late final AnimationController _press;
  bool _reduced = false, _foreground = true, _opening = false, _tickerEnabled = true;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _glow = AnimationController(vsync:this,duration:const Duration(milliseconds:2600));
    _press = AnimationController(vsync:this,duration:const Duration(milliseconds:180));
  }
  void _sync() {
    if (_reduced || !_foreground || !_tickerEnabled) { _glow.stop(); }
    else if (!_glow.isAnimating) { _glow.repeat(reverse:true); }
  }
  @override void didChangeDependencies() {
    super.didChangeDependencies(); _reduced=MediaQuery.disableAnimationsOf(context); _tickerEnabled=TickerMode.of(context); _sync();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground=state==AppLifecycleState.resumed; if(mounted)_sync();
  }
  Future<void> _create() async {
    if(_opening)return;
    setState(()=>_opening=true);
    HapticFeedback.selectionClick();
    try {
      if(!_reduced){await _press.forward(from:0).orCancel;if(!mounted)return;_press.reverse();}
      await widget.onCreate();
    } on TickerCanceled { /* Widget was removed during the press animation. */ }
    finally { if(mounted)setState(()=>_opening=false); }
  }
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);_glow.dispose();_press.dispose();super.dispose();}

  Widget _tab(int index,IconData icon,String label)=>Expanded(child:Semantics(
    selected:widget.index==index,button:true,
    child:InkWell(onTap:()=>widget.onTab(index),borderRadius:BorderRadius.circular(22),
      child:AnimatedContainer(duration:_reduced?Duration.zero:const Duration(milliseconds:220),
        height:44,decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),
          color:widget.index==index?const Color(0x20FFE0EF):Colors.transparent),
        child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          Icon(icon,size:23,color:widget.index==index?const Color(0xFFFFD5E6):Colors.white60),
          const SizedBox(width:8),Flexible(child:Text(label,maxLines:1,overflow:TextOverflow.ellipsis,
            style:TextStyle(fontSize:11,color:widget.index==index?Colors.white:Colors.white60))),
        ])))));

  @override Widget build(BuildContext context)=>SafeArea(top:false,child:Padding(
    padding:const EdgeInsets.fromLTRB(18,10,18,12),child:SizedBox(height:68,
      child:Stack(clipBehavior:Clip.none,children:[
        Positioned.fill(child:IgnorePointer(child:ClipPath(
          clipper:const _EncounterDockClipper(),
          child:BackdropFilter(filter:ui.ImageFilter.blur(sigmaX:8,sigmaY:8),
            child:const ColoredBox(color:Color(0x6B33202C))),
        ))),
        const Positioned.fill(child:IgnorePointer(
          child:CustomPaint(painter:_EncounterDockBorder()),
        )),
        Positioned(top:16,left:5,right:5,height:44,child:Row(children:[
          _tab(0,Icons.explore_outlined,'encounter.explore'.tr),
          const SizedBox(width:68),
          _tab(1,Icons.chat_bubble_outline_rounded,'encounter.chat'.tr),
        ])),
        Positioned(top:2,left:0,right:0,child:Center(child:AnimatedBuilder(animation:Listenable.merge([_glow,_press]),
          builder:(context,_) {
            final wave=_reduced?0.5:Curves.easeInOut.transform(_glow.value);
            final press=Curves.easeOutCubic.transform(_press.value);
            return Transform.scale(scale:1-press*.07,child:Transform.rotate(angle:press*math.pi/2,
              child:Semantics(button:true,label:'encounter.create'.tr,
                child:GestureDetector(onTap:_create,behavior:HitTestBehavior.opaque,
                  child:SizedBox(width:60,height:60,child:Stack(alignment:Alignment.center,children:[
                    Container(width:52,height:52,decoration:BoxDecoration(shape:BoxShape.circle,
                      gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
                        colors:[Color(0xFFFFE3EC),Color(0xFFD98DAE),Color(0xFF915C8E)]),
                      border:Border.all(color:const Color(0xBBFFF1F5),width:1.2),
                      boxShadow:[BoxShadow(color:const Color(0xFFEBA2B8).withValues(alpha:.18+wave*.16),
                        blurRadius:16+wave*8,spreadRadius:wave*2)])),
                    const Icon(Icons.add_rounded,color:Color(0xFF351B30),size:28),
                    Positioned(top:1,right:3,child:IgnorePointer(child:Opacity(opacity:.45+wave*.45,
                      child:const Icon(Icons.auto_awesome_rounded,color:Color(0xFFFFE9F2),size:14)))),
                  ]))))));
          }))),
      ]))));
}

/// Shared glass and border outline. Tabs have four pixels of inset on every
/// outer side; only the upper half of the center action adds a curved rise.
Path encounterDockOutline(Size size) => Path.combine(
  PathOperation.union,
  Path()..addRRect(RRect.fromRectAndRadius(
    Rect.fromLTRB(1, 12, size.width - 1, 64), const Radius.circular(26))),
  Path()
    ..moveTo(size.width / 2 - 30, 32)
    ..arcTo(
      Rect.fromCircle(center: Offset(size.width / 2, 32), radius: 30),
      math.pi, math.pi, false,
    )
    ..close(),
);

class _EncounterDockClipper extends CustomClipper<Path> {
  const _EncounterDockClipper();
  @override
  Path getClip(Size size) => encounterDockOutline(size);
  @override
  bool shouldReclip(covariant _EncounterDockClipper oldClipper) => false;
}

class _EncounterDockBorder extends CustomPainter {
  const _EncounterDockBorder();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(encounterDockOutline(size), Paint()
      ..color = const Color(0x36FFE6F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }
  @override
  bool shouldRepaint(covariant _EncounterDockBorder oldDelegate) => false;
}
