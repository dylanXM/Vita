import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../shared/media_image.dart';
import 'encounter_portrait.dart';

class EncounterAvatar extends StatelessWidget {
 const EncounterAvatar({super.key,required this.url,this.size=40});
 final String url;final double size;
 @override Widget build(BuildContext context)=>ClipOval(child:SizedBox(width:size,height:size,
  child:url.isEmpty?const ColoredBox(color:Color(0xFF33202C),child:Icon(Icons.person,color:Colors.white70)):
    url.startsWith('/v1/encounter-art/')?Image.network(Uri.parse(vitaApiBaseUrl).resolve(url).toString(),fit:BoxFit.cover,alignment:Alignment.topCenter,errorBuilder:(_,__,___)=>const Icon(Icons.person,color:Colors.white70)):
    VitaMediaImage(url:url,errorBuilder:(_,__,___)=>const Icon(Icons.person,color:Colors.white70))));
}
class EncounterProfilePage extends StatefulWidget {
 const EncounterProfilePage({super.key,required this.character});final Map<String,dynamic> character;
 @override State<EncounterProfilePage> createState()=>_EncounterProfilePageState();
}
class _EncounterProfilePageState extends State<EncounterProfilePage>{
 late Map<String,dynamic> _character;bool _busy=false,_sharing=false;
 @override void initState(){super.initState();_character=Map.from(widget.character);}
 void _error(){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.error'.tr)));}
 Future<void> _follow()async{
  if(_busy)return;setState(()=>_busy=true);
  try{final result=await ApiClient.instance.put('/v1/encounters/characters/${_character['id']}/follow',data:{'following':_character['is_following']!=true});if(mounted)setState(()=>_character.addAll(Map<String,dynamic>.from(result as Map)));}catch(_){_error();}finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _share(BuildContext anchor)async{
  if(_sharing)return;setState(()=>_sharing=true);
  final box=anchor.findRenderObject() as RenderBox?;
  final origin=box==null?const Rect.fromLTWH(0,0,1,1):box.localToGlobal(Offset.zero)&box.size;
  Dio? external;
  try{
   final cover='${_character['cover_url']??''}';
   final Dio client;
   if(cover.startsWith('/v1/')){client=ApiClient.instance.dio;}else{final publicClient=Dio(BaseOptions(connectTimeout:const Duration(seconds:10),receiveTimeout:const Duration(seconds:30)));external=publicClient;client=publicClient;}
   final response=await client.get<List<int>>(cover,options:Options(responseType:ResponseType.bytes));
   final bytes=response.data;if(bytes==null||bytes.isEmpty||bytes.length>16*1024*1024)throw ApiException('encounter.error'.tr);
   final mime=(response.headers.value('content-type')??'image/png').split(';').first;
   final ext=mime=='image/jpeg'?'jpg':mime=='image/webp'?'webp':mime=='image/gif'?'gif':'png';
   final dir=await getTemporaryDirectory();final file=File('${dir.path}/encounter-${_character['id']}-${DateTime.now().microsecondsSinceEpoch}.$ext');await file.writeAsBytes(bytes);
   final tags=(_character['tags'] as List? ?? []).join(' · ');
   final link=_character['is_private']==true?'':Uri.parse(vitaApiBaseUrl).resolve('/v1/encounters/share/${_character['id']}').toString();
   if(!mounted)return;
   await Share.shareXFiles([XFile(file.path,mimeType:mime)],text:'${_character['name']} · ${_character['age']}\n$tags\n${_character['description']??''}\n$link',sharePositionOrigin:origin);
  }catch(_){_error();}finally{external?.close();if(mounted)setState(()=>_sharing=false);}
 }
 @override Widget build(BuildContext context)=>Theme(data:ThemeData.dark().copyWith(colorScheme:const ColorScheme.dark(primary:Color(0xFFEBA2B8),surface:Color(0xFF2A202A))),child:Scaffold(backgroundColor:const Color(0xFF151016),appBar:AppBar(backgroundColor:const Color(0xFF151016),title:Text('${_character['name']}'),actions:[Builder(builder:(anchor)=>IconButton(onPressed:_sharing||_character['enabled']==false?null:()=>_share(anchor),icon:const Icon(Icons.ios_share),tooltip:'encounter.share'.tr))]),body:ListView(padding:const EdgeInsets.all(22),children:[
  SizedBox(height:380,child:ClipRRect(borderRadius:BorderRadius.circular(24),child:EncounterPortrait(character:_character))),const SizedBox(height:20),
  Row(children:[EncounterAvatar(url:'${_character['avatar_url']??''}',size:52),const SizedBox(width:12),Expanded(child:Text('${_character['name']} · ${_character['age']}',style:const TextStyle(fontSize:23,fontWeight:FontWeight.w700)))]),const SizedBox(height:12),
  Wrap(spacing:8,runSpacing:8,children:(_character['tags'] as List? ?? []).map((tag)=>Chip(label:Text('$tag'))).toList()),
  Text('${_character['personality']??''}',style:const TextStyle(color:Color(0xFFEBA2B8))),const SizedBox(height:12),Text('${_character['description']??''}',style:const TextStyle(height:1.6)),const SizedBox(height:20),
  Text('encounter.followers'.trParams({'count':'${_character['follower_count']??0}'})),const SizedBox(height:12),
  FilledButton.icon(onPressed:_busy||(_character['enabled']==false&&_character['is_following']!=true)?null:_follow,icon:Icon(_character['is_following']==true?Icons.favorite:Icons.favorite_border),label:Text((_character['is_following']==true?'encounter.unfollow':'encounter.follow').tr)),
  TextButton.icon(onPressed:()=>Get.to(()=>EncounterReportPage(character:_character),transition:Transition.cupertino),icon:const Icon(Icons.flag_outlined),label:Text('encounter.report'.tr)),
 ])));
}
class EncounterReportPage extends StatefulWidget {
 const EncounterReportPage({super.key,required this.character});final Map<String,dynamic> character;
 @override State<EncounterReportPage> createState()=>_EncounterReportPageState();
}
class _EncounterReportPageState extends State<EncounterReportPage>{
 final _details=TextEditingController(),_contact=TextEditingController();String _reason='inappropriate';bool _busy=false;
 Map<String,dynamic>? _submitted;
 @override void dispose(){_details.dispose();_contact.dispose();super.dispose();}
 Future<void> _submit()async{
  if(_busy||_details.text.trim().runes.length<10)return;
  _submitted??={'reason':_reason,'details':_details.text.trim(),'contact':_contact.text.trim(),'idempotency_key':'report-${DateTime.now().microsecondsSinceEpoch}'};
  setState(()=>_busy=true);
  try{await ApiClient.instance.post('/v1/encounters/characters/${widget.character['id']}/reports',data:_submitted);if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.reportReceived'.tr)));Get.back(result:true);}
  on ApiException catch(e){if(e.statusCode!=null&&e.statusCode!<500)_submitted=null;if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.error'.tr)));}
  catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.error'.tr)));}finally{if(mounted)setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context)=>Theme(data:ThemeData.dark().copyWith(colorScheme:const ColorScheme.dark(primary:Color(0xFFEBA2B8),surface:Color(0xFF2A202A))),child:Scaffold(backgroundColor:const Color(0xFF151016),appBar:AppBar(backgroundColor:const Color(0xFF151016),title:Text('encounter.report'.tr)),body:ListView(padding:const EdgeInsets.all(24),children:[
  Text('${widget.character['name']}'),const SizedBox(height:16),Wrap(spacing:8,runSpacing:8,children:['inappropriate','harassment','misleading','other'].map((reason)=>ChoiceChip(label:Text('encounter.reason_$reason'.tr),selected:_reason==reason,onSelected:_busy||_submitted!=null?null:(_)=>setState(()=>_reason=reason))).toList()),
  TextField(controller:_details,onChanged:(_)=>setState((){}),enabled:!_busy&&_submitted==null,maxLength:2000,maxLines:6,decoration:InputDecoration(labelText:'encounter.reportDetails'.tr)),
  TextField(controller:_contact,enabled:!_busy&&_submitted==null,maxLength:200,decoration:InputDecoration(labelText:'encounter.contact'.tr)),
  FilledButton(onPressed:_busy||(_submitted==null&&_details.text.trim().runes.length<10)?null:_submit,child:Text('encounter.submitReport'.tr)),
 ])));
}
