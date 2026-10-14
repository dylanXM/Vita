import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../shared/media_image.dart';

/// Upper portrait swipes select photos; lower card swipes still select characters.
class EncounterPortrait extends StatefulWidget {
  const EncounterPortrait({super.key,required this.character});
  final Map<String,dynamic> character;
  @override State<EncounterPortrait> createState()=>_EncounterPortraitState();
}
class _EncounterPortraitState extends State<EncounterPortrait> {
  int _index=0;
  double _drag=0;
  List<String> get _images {
    final images=(widget.character['image_urls'] as List? ?? []).whereType<String>().where((s)=>s.isNotEmpty).take(3).toList();
    return images.isEmpty?['${widget.character['cover_url']??''}']:images;
  }
  @override void didUpdateWidget(covariant EncounterPortrait oldWidget){super.didUpdateWidget(oldWidget);if(_index>=_images.length)_index=0;}
  @override Widget build(BuildContext context){
    final images=_images;
    return LayoutBuilder(builder:(context,size)=>Stack(fit:StackFit.expand,children:[
      VitaMediaImage(url:images[_index],errorBuilder:(_,__,___)=>const ColoredBox(
        color:Color(0xFF2A202A),child:Icon(Icons.person,size:80,color:Color(0xFFEBA2B8)))),
      if(images.length>1)Positioned(left:0,right:0,top:0,height:size.maxHeight*.6,
        child:GestureDetector(behavior:HitTestBehavior.opaque,
          onHorizontalDragStart:(_)=>_drag=0,
          onHorizontalDragUpdate:(details)=>_drag+=details.delta.dx,
          onHorizontalDragEnd:(details){
          final velocity=details.primaryVelocity??0;if(velocity.abs()<100&&_drag.abs()<28)return;
          final rtl=Directionality.of(context)==TextDirection.rtl;
          final direction=_drag.abs()>=28?_drag:velocity;
          final next=(direction<0?1:-1)*(rtl?-1:1);
          setState(()=>_index=(_index+next+images.length)%images.length);
        })),
      if(images.length>1)Positioned(left:20,right:20,top:14,child:Row(children:[
        for(var i=0;i<images.length;i++)Expanded(child:Semantics(button:true,
          label:'encounter.imageNumber'.trParams({'number':'${i+1}'}),selected:_index==i,
          child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:()=>setState(()=>_index=i),
            child:SizedBox(height:44,child:Center(child:Container(height:3,
              margin:const EdgeInsets.symmetric(horizontal:3),
              decoration:BoxDecoration(color:_index==i?Colors.white:Colors.white38,
                borderRadius:BorderRadius.circular(4)))))))),
      ])),
    ]));
  }
}
