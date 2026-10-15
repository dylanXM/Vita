import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api_client.dart';
import '../../shared/media_image.dart';
import 'encounter_media.dart';
import 'encounter_chat_backdrop.dart';
import 'encounter_dock.dart';
import 'encounter_deck.dart';
import 'encounter_purchase_sheet.dart';
import 'encounter_portrait.dart';
import 'encounter_profile.dart';

const _night = Color(0xFF151016);
const _rose = Color(0xFFEBA2B8);
const _panel = Color(0xFF2A202A);
final _encounterTheme = ThemeData.dark().copyWith(scaffoldBackgroundColor:_night,colorScheme:const ColorScheme.dark(primary:_rose,surface:_panel));
String _s(Map value, String key) => '${value[key] ?? ''}';
String _requestKey() => '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';

class EncountersPage extends StatefulWidget {
 const EncountersPage({super.key});
 @override State<EncountersPage> createState() => _EncountersPageState();
}
class _EncountersPageState extends State<EncountersPage> {
 List<Map<String,dynamic>> _characters=[],_chats=[];
 bool _loading=true,_configured=false;
 String _gender='',_personality=''; int _tab=0;
 int _deckRevision=0;
 @override void initState(){super.initState();_load();}
 void _error(){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.error'.tr)));}
 Future<void> _load() async {
  try {
   final chars=await ApiClient.instance.get('/v1/encounters/characters');
   final prefs=await ApiClient.instance.get('/v1/encounters/preferences');
   final chats=await ApiClient.instance.get('/v1/encounters/conversations');
   if(!mounted)return;
   setState((){_characters=List<Map<String,dynamic>>.from((chars['items'] as List).map((e)=>Map<String,dynamic>.from(e as Map)));_chats=List<Map<String,dynamic>>.from((chats['items'] as List).map((e)=>Map<String,dynamic>.from(e as Map)));_configured=prefs['configured']==true;_gender=_s(prefs,'gender');_personality=_s(prefs,'personality');_loading=false;});
  } catch(_){if(mounted)setState(()=>_loading=false);_error();}
 }
 Future<void> _preferences() async {
  final choice=await Get.to<Map<String,dynamic>>(()=>_EncounterForm(preferences:true,initial:{'gender':_gender,'personality':_personality},personalities:_characters.expand((e)=>[_s(e,'personality'),...(e['tags'] as List? ?? []).whereType<String>()]).where((e)=>e.isNotEmpty).toSet().toList()),transition:Transition.cupertino);
  if(choice==null||!mounted)return;
  try{await ApiClient.instance.put('/v1/encounters/preferences',data:choice);if(!mounted)return;setState((){_configured=true;_gender=_s(choice,'gender');_personality=_s(choice,'personality');});await _load();if(mounted)setState(()=>_deckRevision++);}catch(_){_error();}
 }
 Future<void> _open(Map<String,dynamic> character,{bool gift=false}) async {
  try {
   final result=await ApiClient.instance.post('/v1/encounters/conversations',data:{'character_id':character['id']});
   if(!mounted)return;
   await Get.to(()=>EncounterChatPage(id:_s(result,'id'),name:_s(character,'name'),cover:_s(character,'cover_url'),avatar:_s(character,'avatar_url'),characterId:_s(character,'id'),gift:gift),transition:Transition.cupertino);
   if(mounted)_load();
  } catch(_){_error();}
 }
 Future<void> _createCharacter() async {
  if(!_configured){await _preferences();return;}
  final created=await Get.to<Map<String,dynamic>>(()=>const _EncounterForm(),transition:Transition.cupertino);
  if(created!=null&&mounted){await _load();if(mounted)await _open(created);}
 }
 @override Widget build(BuildContext context){
  final filtered=_characters;
  return Theme(data:_encounterTheme,child:Scaffold(backgroundColor:_night,extendBody:true,
   appBar:AppBar(backgroundColor:_night,title:Text('encounter.title'.tr),actions:[IconButton(onPressed:_preferences,icon:const Icon(Icons.tune_rounded),tooltip:'encounter.preferences'.tr)]),
   body:_loading?const Center(child:CircularProgressIndicator()):!_configured?Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.auto_awesome,color:_rose,size:40),const SizedBox(height:18),Text('encounter.welcome'.tr,textAlign:TextAlign.center,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w600)),const SizedBox(height:24),FilledButton(onPressed:_preferences,child:Text('encounter.preferences'.tr))]))):_tab==0?
    filtered.isEmpty?Center(child:TextButton(onPressed:_preferences,child:Text('encounter.empty'.tr))):LayoutBuilder(builder:(context,box)=>Padding(padding:const EdgeInsets.fromLTRB(24,18,24,110),child:EncounterDeck(key:ValueKey(_deckRevision),itemCount:filtered.length,itemBuilder:(context,index)=>ClipRRect(borderRadius:BorderRadius.circular(28),child:Stack(fit:StackFit.expand,children:[EncounterPortrait(key:ValueKey(filtered[index]['id']),character:filtered[index]),const IgnorePointer(child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,Color(0x22000000),Color(0xEE171018)],stops:[0,.45,1])))),
      Positioned(left:22,right:22,bottom:22,child:ConstrainedBox(constraints:BoxConstraints(maxHeight:max(80.0,box.maxHeight-110)),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[InkWell(onTap:()async{await Get.to(()=>EncounterProfilePage(character:filtered[index]),transition:Transition.cupertino);if(mounted)await _load();},child:Text('${filtered[index]['name']} · ${filtered[index]['age']??25}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w700,color:Colors.white))),Text(_s(filtered[index],'personality'),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:_rose)),const SizedBox(height:8),Text((filtered[index]['tags'] as List? ?? []).join(' · '),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white70)),Text('encounter.followers'.trParams({'count':'${filtered[index]['follower_count']??0}'}),style:const TextStyle(color:Colors.white70)),Text(_s(filtered[index],'description'),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,height:1.5)),const SizedBox(height:18),Row(children:[IconButton(onPressed:()=>_open(filtered[index],gift:true),icon:const Icon(Icons.card_giftcard,color:_rose),tooltip:'encounter.gift'.tr),const SizedBox(width:12),Expanded(child:FilledButton(onPressed:()=>_open(filtered[index]),child:Text('encounter.chat'.tr)))])]))))
     ]))))):RefreshIndicator(onRefresh:_load,child:ListView.builder(padding:const EdgeInsets.only(bottom:110),physics:const AlwaysScrollableScrollPhysics(),itemCount:_chats.length,itemBuilder:(context,index){final c=_chats[index];return SizedBox(height:80,child:ListTile(leading:ClipRRect(borderRadius:BorderRadius.circular(14),child:SizedBox(width:52,height:52,child:EncounterAvatar(url:_s(c,'avatar_url'),size:52))),title:Text(_s(c,'name'),maxLines:1,overflow:TextOverflow.ellipsis),onTap:()=>Get.to(()=>EncounterChatPage(id:_s(c,'id'),name:_s(c,'name'),cover:_s(c,'cover_url'),avatar:_s(c,'avatar_url'),characterId:_s(c,'character_id')),transition:Transition.cupertino)));})),
   bottomNavigationBar:EncounterDock(index:_tab,onTab:(index)=>setState(()=>_tab=index),onCreate:_createCharacter),
  ));
 }
}

class _EncounterForm extends StatefulWidget {
 const _EncounterForm({this.preferences=false,this.initial=const {},this.personalities=const []});
 final bool preferences; final Map<String,dynamic> initial; final List<String> personalities;
 @override State<_EncounterForm> createState()=>_EncounterFormState();
}
class _EncounterFormState extends State<_EncounterForm>{
 final _name=TextEditingController(),_persona=TextEditingController(),_traits=TextEditingController(),_age=TextEditingController(text:'25'),_tags=TextEditingController(),_description=TextEditingController();
 String _avatar='';
 late String _gender; String _cover='';bool _busy=false;final _imageURLs=<String>[];
 @override void initState(){super.initState();_gender=_s(widget.initial,'gender');_traits.text=_s(widget.initial,'personality');if(!widget.preferences)_gender='female';}
 @override void dispose(){_name.dispose();_persona.dispose();_traits.dispose();_age.dispose();_tags.dispose();_description.dispose();super.dispose();}
 Future<void> _pick()async{if(_busy||_imageURLs.length>=3)return;setState(()=>_busy=true);try{final image=await ImagePicker().pickImage(source:ImageSource.gallery,maxWidth:1024,imageQuality:90);if(image!=null){final result=await ApiClient.instance.upload('/v1/companions/image',image.path,kind:'image');if(mounted)setState((){_imageURLs.add('/v1/media/${result['id']}');_cover=_imageURLs.first;});}}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.error'.tr)));}finally{if(mounted)setState(()=>_busy=false);}}
 Future<void> _pickAvatar()async{
  if(_busy)return;setState(()=>_busy=true);try{final image=await ImagePicker().pickImage(source:ImageSource.gallery,maxWidth:1024,imageQuality:90);if(image!=null){final result=await ApiClient.instance.upload('/v1/companions/image',image.path,kind:'image');if(mounted)setState(()=>_avatar='/v1/media/${result['id']}');}}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.error'.tr)));}finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _save()async{
  if(widget.preferences){Get.back(result:{'gender':_gender,'personality':_traits.text});return;}
  if(_busy||_name.text.trim().isEmpty||_cover.isEmpty||(int.tryParse(_age.text)??0)<18||(int.tryParse(_age.text)??101)>100)return;
  setState(()=>_busy=true);try{final result=await ApiClient.instance.post('/v1/encounters/characters',data:{'name':_name.text.trim(),'gender':_gender,'personality':_traits.text.trim(),'persona':_persona.text.trim(),'age':int.parse(_age.text),'tags':_tags.text.split(RegExp('[,，]')).map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList(),'description':_description.text.trim(),'cover_url':_cover,'avatar_url':_avatar,'image_urls':_imageURLs,'enabled':true});if(mounted)Get.back(result:Map<String,dynamic>.from(result as Map));}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.error'.tr)));}finally{if(mounted)setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context)=>Theme(data:_encounterTheme,child:Scaffold(backgroundColor:_night,appBar:AppBar(backgroundColor:_night,title:Text((widget.preferences?'encounter.preferences':'encounter.create').tr)),body:ListView(padding:const EdgeInsets.all(24),children:[
  Text('encounter.gender'.tr),Wrap(spacing:8,children:[if(widget.preferences)'','male','female','other'].map((g)=>ChoiceChip(label:Text('encounter.${g.isEmpty?'any':g}'.tr),selected:_gender==g,onSelected:_busy?null:(_)=>setState(()=>_gender=g))).toList()),const SizedBox(height:24),
  if(widget.preferences)Wrap(spacing:8,runSpacing:8,children:['',...widget.personalities].map((p)=>ChoiceChip(label:Text(p.isEmpty?'encounter.any'.tr:p),selected:_traits.text==p,onSelected:(_)=>setState(()=>_traits.text=p))).toList()) else ...[
   TextField(controller:_name,maxLength:80,decoration:InputDecoration(labelText:'encounter.name'.tr)),TextField(controller:_age,keyboardType:TextInputType.number,maxLength:3,decoration:InputDecoration(labelText:'encounter.age'.tr)),TextField(controller:_tags,decoration:InputDecoration(labelText:'encounter.tags'.tr)),TextField(controller:_description,maxLength:500,maxLines:3,decoration:InputDecoration(labelText:'encounter.description'.tr)),OutlinedButton.icon(onPressed:_busy?null:_pickAvatar,icon:const Icon(Icons.account_circle_outlined),label:Text('encounter.avatar'.tr)),if(_avatar.isNotEmpty)EncounterAvatar(url:_avatar,size:64),TextField(controller:_traits,maxLength:200,decoration:InputDecoration(labelText:'encounter.personality'.tr)),TextField(controller:_persona,maxLength:500,maxLines:4,decoration:InputDecoration(labelText:'encounter.persona'.tr)),const SizedBox(height:16),Text('encounter.imagesHint'.tr),OutlinedButton.icon(onPressed:_busy||_imageURLs.length>=3?null:_pick,icon:const Icon(Icons.add_photo_alternate_outlined),label:Text('encounter.cover'.tr)),Wrap(spacing:8,runSpacing:8,children:[for(var i=0;i<_imageURLs.length;i++)SizedBox(width:84,height:112,child:Stack(fit:StackFit.expand,children:[ClipRRect(borderRadius:BorderRadius.circular(12),child:VitaMediaImage(url:_imageURLs[i])),Positioned(right:0,top:0,child:IconButton(onPressed:_busy?null:(){setState((){_imageURLs.removeAt(i);_cover=_imageURLs.isEmpty?'':_imageURLs.first;});},icon:const Icon(Icons.close_rounded),tooltip:'encounter.removeImage'.tr))]))]),
  ],const SizedBox(height:24),FilledButton(onPressed:_busy?null:_save,child:Text('encounter.continue'.tr)),if(_busy)const Center(child:CircularProgressIndicator())
 ])));
}

class EncounterChatPage extends StatefulWidget {
 const EncounterChatPage({super.key,required this.id,required this.name,required this.cover,this.avatar='',this.characterId='',this.gift=false});
 final String id,name,cover,avatar,characterId; final bool gift;
 @override State<EncounterChatPage> createState()=>_EncounterChatPageState();
}
class _EncounterChatPageState extends State<EncounterChatPage> with WidgetsBindingObserver {
 final _input=TextEditingController(),_scroll=ScrollController(); List<Map<String,dynamic>> _messages=[];
 bool _busy=false,_bottom=true; Map<String,dynamic>? _pending;
 Timer? _poll; int _pollCount=0; bool _loadingMessages=false,_foreground=true;
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_scroll.addListener(()=>_bottom=_scroll.hasClients&&_scroll.position.extentAfter<=24);_load();if(widget.gift)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)_purchase('gift');});}
 @override void dispose(){_poll?.cancel();WidgetsBinding.instance.removeObserver(this);_input.dispose();_scroll.dispose();super.dispose();}
 @override void didChangeAppLifecycleState(AppLifecycleState state){_foreground=state==AppLifecycleState.resumed;}
 @override void didChangeMetrics(){if(_bottom)_follow();}
 void _follow(){WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&_scroll.hasClients)_scroll.jumpTo(_scroll.position.maxScrollExtent);});}
 void _error(){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('encounter.error'.tr)));}
 Future<void> _load()async{
  if(_loadingMessages)return;_loadingMessages=true;
  try{final result=await ApiClient.instance.get('/v1/encounters/conversations/${widget.id}/messages');if(!mounted)return;final follow=_bottom;
   setState((){_messages=List<Map<String,dynamic>>.from((result['items'] as List).map((e)=>Map<String,dynamic>.from(e as Map)));if(result['processing_request'] is Map){_pending=Map<String,dynamic>.from(result['processing_request'] as Map);}else if(!_busy){_pending=null;}});
   if(result['processing_request'] is Map){_startPolling();}else{_poll?.cancel();_poll=null;}
   if(follow)_follow();
  }catch(_){if(_poll==null)_error();}finally{_loadingMessages=false;}
 }
 void _startPolling(){
  if(_poll!=null)return;_pollCount=0;
  _poll=Timer.periodic(const Duration(seconds:5),(timer){if(!mounted||_pollCount>=60){timer.cancel();_poll=null;return;}if(_foreground&&!_loadingMessages){_pollCount++;_load();}});
 }
 Future<void> _send([Map<String,dynamic>? paid])async{
  if(_busy)return;
  final data=_pending??paid??{'content':_input.text.trim(),'idempotency_key':_requestKey()};if(_s(data,'content').isEmpty)return;
  setState((){_busy=true;_pending=data;});_bottom=true;_follow();
  String suggested='';
  try{final result=await ApiClient.instance.post('/v1/encounters/conversations/${widget.id}/messages',data:data);if(!mounted)return;suggested=_s(result,'media_request');setState(()=>_pending=null);if(_s(data,'product_key').isEmpty)_input.clear();if(data['product_key']!=null){final sync=ApiClient.onPaidActionSuccess;if(sync!=null){try{await sync();}catch(_){}}}await _load();}
  on ApiException catch(e){if(e.code=='insufficient_credits'){_pending=null;await Get.toNamed('/credits');}else if(e.code=='experience_requires_subscription'){_pending=null;await Get.toNamed('/subscription');}else if(e.code!='request_processing'&&e.code!='settlement_pending'&&e.statusCode!=null&&e.statusCode! < 500){_pending=null;}_error();}
  catch(_){_error();}finally{if(mounted){setState(()=>_busy=false);if(_pending!=null)_startPolling();}}
  if(mounted&&(suggested=='photo'||suggested=='video'))await _purchase(suggested);
 }
 Future<void> _purchase(String category)async{
  if(_busy||_pending!=null)return;
  try{
   final catalog=await ApiClient.instance.get('/v1/encounters/catalog');if(!mounted)return;
   final products=(catalog['products'] as List).where((e)=>category=='video'?e['key']=='encounter_video':e['category']==category&&e['key']!='encounter_video').toList();
   final icon=category=='gift'?Icons.card_giftcard:category=='video'?Icons.movie_outlined:Icons.image_outlined;
   final title='encounter.$category'.tr;
   final product=await showEncounterSheet<Map<String,dynamic>>(context,Builder(builder:(sheet)=>EncounterSheetContent(
    title:title,icon:icon,children:[
     if(products.isEmpty) ...[
      const SizedBox(height:12),
      Text('encounter.unavailable'.tr,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white60)),
      const SizedBox(height:28),
     ] else ...[
      Text('${'credits.balance'.tr}: ${catalog['balance']} ◈',style:const TextStyle(color:_rose)),
      const SizedBox(height:16),
      ...products.map((p)=>EncounterProductTile(product:Map<String,dynamic>.from(p as Map),
       onTap:()=>Navigator.of(sheet).pop(Map<String,dynamic>.from(p as Map)))),
     ],
    ],
   )));
   if(product==null||!mounted)return;
   if(catalog['is_subscribed']!=true){
    final subscribe=await showEncounterSheet<bool>(context,Builder(builder:(sheet)=>EncounterSheetContent(
     title:'subscription.required.title'.tr,icon:Icons.favorite_border_rounded,children:[
      FilledButton(onPressed:()=>Navigator.of(sheet).pop(true),child:Text('encounter.continue'.tr)),
      TextButton(onPressed:()=>Navigator.of(sheet).pop(false),child:Text('encounter.cancel'.tr)),
     ],
    )));
    if(subscribe==true&&mounted)await Get.toNamed('/subscription');return;
   }
   if((catalog['balance'] as num)<(product['coins'] as num)){await Get.toNamed('/credits');return;}
   String demand;
   if(category=='gift'){demand='encounter.giftMessage'.trParams({'gift':_s(product,'name_key').tr});}else{
    final request=await showEncounterSheet<String>(context,const EncounterDemandSheet());if(request==null||!mounted)return;demand=request;
   }
   final confirmed=await showEncounterSheet<bool>(context,Builder(builder:(sheet)=>EncounterSheetContent(
    title:'encounter.confirm'.tr,icon:icon,children:[
     Text('${product['emoji']??''} ${_s(product,'name_key').tr}',style:const TextStyle(fontSize:18)),
     const SizedBox(height:12),
     Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(
      color:const Color(0x440F0A12),borderRadius:BorderRadius.circular(18)),
      child:Text(demand,style:const TextStyle(color:Colors.white70,height:1.6))),
     const SizedBox(height:22),
     Text('${product['coins']} ◈',textAlign:TextAlign.center,style:const TextStyle(color:_rose,fontSize:32,fontWeight:FontWeight.w500)),
     Text('${'credits.balance'.tr}: ${catalog['balance']} ◈',textAlign:TextAlign.center,style:const TextStyle(color:Colors.white54)),
     const SizedBox(height:16),
     Text('encounter.refund'.tr,style:const TextStyle(color:Colors.white54,fontSize:12),textAlign:TextAlign.center),
     const SizedBox(height:24),
     FilledButton(onPressed:()=>Navigator.of(sheet).pop(true),child:Text('encounter.confirm'.tr)),
     TextButton(onPressed:()=>Navigator.of(sheet).pop(false),child:Text('encounter.cancel'.tr)),
    ],
   )));
   if(confirmed==true&&mounted)_send({'content':demand,'idempotency_key':_requestKey(),'product_key':product['key'],'quoted_coins':product['coins']});
  }catch(_){_error();}
 }
 @override Widget build(BuildContext context)=>Theme(data:_encounterTheme,child:Stack(fit:StackFit.expand,children:[
  Positioned.fill(child:MediaQuery.removeViewInsets(context:context,removeBottom:true,
    child:EncounterChatBackdrop(cover:widget.cover))),
  Scaffold(backgroundColor:Colors.transparent,resizeToAvoidBottomInset:true,
   appBar:AppBar(backgroundColor:Colors.transparent,surfaceTintColor:Colors.transparent,scrolledUnderElevation:0,title:Row(children:[ClipRRect(borderRadius:BorderRadius.circular(10),child:SizedBox(width:36,height:36,child:EncounterAvatar(url:widget.avatar,size:36))),const SizedBox(width:12),Expanded(child:InkWell(onTap:widget.characterId.isEmpty?null:()async{try{final role=await ApiClient.instance.get('/v1/encounters/characters/${widget.characterId}');if(mounted)await Get.to(()=>EncounterProfilePage(character:Map<String,dynamic>.from(role as Map)),transition:Transition.cupertino);}catch(_){_error();}},child:Text(widget.name,maxLines:1,overflow:TextOverflow.ellipsis))),if(_busy||_pending!=null)Text('encounter.replying'.tr,style:const TextStyle(fontSize:12,color:_rose))])),body:SafeArea(top:false,child:Column(children:[Expanded(child:RefreshIndicator(onRefresh:_load,child:ListView.builder(controller:_scroll,physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(18),itemCount:_messages.length+(_pending==null?0:1),itemBuilder:(context,index){final m=index<_messages.length?_messages[index]:<String,dynamic>{'sender_type':'user','content':_pending!['content']},own=m['sender_type']=='user';return Align(alignment:own?AlignmentDirectional.centerEnd:AlignmentDirectional.centerStart,child:Container(constraints:BoxConstraints(maxWidth:MediaQuery.sizeOf(context).width*.8),padding:const EdgeInsets.all(14),margin:const EdgeInsets.only(bottom:12),decoration:BoxDecoration(color:own?const Color(0xFF533346):_panel,borderRadius:BorderRadius.circular(18)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[if(_s(m,'content').isNotEmpty)Text(_s(m,'content'),style:const TextStyle(color:Colors.white,height:1.5)),if(_s(m,'media_url').isNotEmpty)SizedBox(width:240,height:240,child:EncounterMedia(url:_s(m,'media_url'),video:m['media_type']=='video'))])));}))),
  Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Row(children:[IconButton(onPressed:_busy?null:()=>_purchase('gift'),icon:const Icon(Icons.card_giftcard,color:_rose),tooltip:'encounter.gift'.tr),IconButton(onPressed:_busy?null:()=>_purchase('photo'),icon:const Icon(Icons.image_outlined,color:_rose),tooltip:'encounter.photo'.tr),IconButton(onPressed:_busy?null:()=>_purchase('video'),icon:const Icon(Icons.movie_outlined,color:_rose),tooltip:'encounter.video'.tr),if(_pending!=null&&!_busy)TextButton(onPressed:_send,child:Text('encounter.retry'.tr))])),
  Padding(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:Row(children:[Expanded(child:TextField(controller:_input,enabled:!_busy&&_pending==null,maxLength:2000,decoration:InputDecoration(hintText:'encounter.message'.tr,counterText:'',filled:true,fillColor:_panel,border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none)))),IconButton(onPressed:_busy?null:_send,icon:const Icon(Icons.arrow_upward_rounded,color:_rose))]))
 ]))),
 ]));
}

