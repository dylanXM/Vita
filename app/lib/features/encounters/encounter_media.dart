import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants.dart';
import '../../core/token_storage.dart';
import '../../shared/media_image.dart';

class EncounterMedia extends StatefulWidget {
 const EncounterMedia({super.key,required this.url,required this.video});
 final String url;final bool video;
 @override State<EncounterMedia> createState()=>_EncounterMediaState();
}
class _EncounterMediaState extends State<EncounterMedia>{
 VideoPlayerController? _player;bool _failed=false;
 @override void initState(){super.initState();if(widget.video)_load();}
 Future<void> _load()async{
  try{final token=await TokenStorage.read();if(!mounted)return;
   final controller=VideoPlayerController.networkUrl(Uri.parse(vitaApiBaseUrl).resolve(widget.url.replaceFirst('/v1/media/','/v1/encounters/media/')),httpHeaders:{if(token!=null)'Authorization':'Bearer $token'});
   _player=controller;await controller.initialize();if(mounted)setState((){});
  }catch(_){if(mounted)setState(()=>_failed=true);}
 }
 @override void dispose(){_player?.dispose();super.dispose();}
 @override Widget build(BuildContext context){
  if(!widget.video)return ClipRRect(borderRadius:BorderRadius.circular(12),child:VitaMediaImage(url:widget.url));
  if(_failed)return Center(child:Text('encounter.error'.tr));
  final p=_player;if(p==null||!p.value.isInitialized)return const Center(child:CircularProgressIndicator());
  return ValueListenableBuilder<VideoPlayerValue>(valueListenable:p,builder:(context,value,_)=>Stack(alignment:Alignment.center,children:[AspectRatio(aspectRatio:value.aspectRatio,child:VideoPlayer(p)),IconButton(onPressed:()=>value.isPlaying?p.pause():p.play(),icon:Icon(value.isPlaying?Icons.pause_circle:Icons.play_circle,size:44,color:Colors.white))]));
 }
}
