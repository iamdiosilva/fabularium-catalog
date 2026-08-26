import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;
import '../models/telegram_storage_channel.dart';
import 'telegram_client.dart';

class TelegramStorageService {
  TelegramStorageService._();
  static final TelegramStorageService instance=TelegramStorageService._();
  static const String defaultChannelTitle='Fabularium Storage';
  static const String defaultChannelAbout='Private storage channel used by Fabularium Catalog. Do not delete files from this channel manually.';
  static const int maxStorageFileBytes=1900*1024*1024;
  static const String _configFileName='storage_channel.json';

  String _configFilePath(){final local=Platform.environment['LOCALAPPDATA'];return p.join(local!=null&&local.isNotEmpty?local:Directory.systemTemp.path,'Fabularium','Telegram',_configFileName);}
  Future<TelegramStorageChannel?> loadChannel() async {final file=File(_configFilePath());try{if(!await file.exists())return null;final decoded=jsonDecode(await file.readAsString());if(decoded is! Map)return null;final map=Map<String,dynamic>.from(decoded);if(map['version']!=1||map['channel'] is! Map)return null;return TelegramStorageChannel.fromJson(Map<String,dynamic>.from(map['channel'] as Map));}catch(_){return null;}}
  Future<void> saveChannel(TelegramStorageChannel channel) async {final file=File(_configFilePath());await file.parent.create(recursive:true);final tmp=File('${file.path}.tmp');await tmp.writeAsString(jsonEncode(<String,dynamic>{'version':1,'channel':channel.toJson()}),flush:true);if(await file.exists())await file.delete();await tmp.rename(file.path);}
  Future<void> selectExistingChannel(TelegramStorageChannel channel)=>saveChannel(channel);
  Future<void> clearChannel() async {for(final file in [File(_configFilePath()),File('${_configFilePath()}.tmp')]){try{if(await file.exists())await file.delete();}catch(_){}}}

  Future<List<TelegramStorageChannel>> listAvailableChannels() async {
    final result=await _runWorker(_listChannelsWorker,const <String,dynamic>{});final raw=result['channels'];if(raw is! List)return <TelegramStorageChannel>[];final ids=<int>{};final channels=<TelegramStorageChannel>[];
    for(final item in raw){if(item is! Map)continue;try{final m=Map<String,dynamic>.from(item);final c=TelegramStorageChannel(id:m['id'] as int,accessHash:m['accessHash'] as int,title:m['title'] as String);if(ids.add(c.id))channels.add(c);}catch(_){}}
    channels.sort((a,b)=>a.title.toLowerCase().compareTo(b.title.toLowerCase()));return channels;
  }
  Future<TelegramStorageChannel> createStorageChannel({String title=defaultChannelTitle,String about=defaultChannelAbout}) async {final r=await _runWorker(_createChannelWorker,<String,dynamic>{'title':title,'about':about});if(r['id'] is! int||r['accessHash'] is! int||r['title'] is! String)throw const TelegramStorageException('Telegram returned invalid storage channel data.');final c=TelegramStorageChannel(id:r['id'] as int,accessHash:r['accessHash'] as int,title:r['title'] as String);await saveChannel(c);return c;}

  Future<Map<String,dynamic>> _runWorker(Future<void> Function(Map<String,dynamic>) entry,Map<String,dynamic> payload) async {
    final events=ReceivePort(),errors=ReceivePort(),exit=ReceivePort();final completer=Completer<Map<String,dynamic>>();Isolate? isolate;Timer? grace;
    late final StreamSubscription es,ers,xs;
    es=events.listen((raw){if(raw is! Map)return;final m=Map<dynamic,dynamic>.from(raw);if(m['type']=='completed'&&!completer.isCompleted){final r=m['result'];completer.complete(r is Map?Map<String,dynamic>.from(r):<String,dynamic>{});}else if(m['type']=='error'&&!completer.isCompleted){completer.completeError(TelegramStorageException(m['error']?.toString()??'Telegram storage error.'));}});
    ers=errors.listen((e){if(!completer.isCompleted)completer.completeError(TelegramStorageException(e is List&&e.isNotEmpty?e.first.toString():e.toString()));});
    xs=exit.listen((_){if(completer.isCompleted)return;grace=Timer(const Duration(seconds:1),(){if(!completer.isCompleted)completer.completeError(const TelegramStorageException('Telegram storage worker stopped unexpectedly.'));});});
    try{isolate=await Isolate.spawn<Map<String,dynamic>>(entry,<String,dynamic>{...payload,'eventPort':events.sendPort},errorsAreFatal:true,onError:errors.sendPort,onExit:exit.sendPort);return await completer.future;}finally{grace?.cancel();isolate?.kill(priority:Isolate.immediate);await es.cancel();await ers.cancel();await xs.cancel();events.close();errors.close();exit.close();}
  }
}

@pragma('vm:entry-point')
Future<void> _listChannelsWorker(Map<String,dynamic> bootstrap) async {final port=bootstrap['eventPort'];if(port is! SendPort)return;final tc=TelegramClient.instance;try{final client=await tc.connect();final response=await client.messages.getDialogs(excludePinned:false,offsetDate:DateTime.fromMillisecondsSinceEpoch(0),offsetId:0,offsetPeer:const t.InputPeerEmpty(),limit:100,hash:0).timeout(const Duration(seconds:30));if(response.error!=null)throw Exception(response.error!.errorMessage);final dynamic result=response.result;final channels=<Map<String,dynamic>>[];if(result!=null){List<dynamic> chats=[];try{chats=List<dynamic>.from(result.chats as List);}catch(_){}for(final raw in chats){if(raw is! t.Channel)continue;final dynamic c=raw;bool broadcast=false,megagroup=false,gigagroup=false,creator=false,canPost=false;String? username;try{broadcast=c.broadcast==true;}catch(_){}try{megagroup=c.megagroup==true;}catch(_){}try{gigagroup=c.gigagroup==true;}catch(_){}if(!broadcast||megagroup||gigagroup)continue;try{username=c.username as String?;}catch(_){}if(username!=null&&username.trim().isNotEmpty)continue;try{creator=c.creator==true;}catch(_){}try{final dynamic ar=c.adminRights;if(ar!=null)canPost=ar.postMessages==true;}catch(_){}if(!creator&&!canPost)continue;try{final int id=c.id as int;final int? hash=c.accessHash as int?;final String title=c.title as String;if(hash!=null&&title.trim().isNotEmpty)channels.add({'id':id,'accessHash':hash,'title':title});}catch(_){}}}port.send({'type':'completed','result':{'channels':channels}});}catch(e,s){port.send({'type':'error','error':e.toString(),'stackTrace':s.toString()});}finally{try{await tc.disconnect();}catch(_){}}}

@pragma('vm:entry-point')
Future<void> _createChannelWorker(Map<String,dynamic> bootstrap) async {final port=bootstrap['eventPort'];if(port is! SendPort)return;final tc=TelegramClient.instance;try{final client=await tc.connect();final response=await client.invoke(t.ChannelsCreateChannel(title:bootstrap['title']?.toString()??TelegramStorageService.defaultChannelTitle,about:bootstrap['about']?.toString()??TelegramStorageService.defaultChannelAbout,broadcast:true,megagroup:false,forImport:false,forum:false)).timeout(const Duration(seconds:30));if(response.error!=null)throw Exception(response.error!.errorMessage);final dynamic updates=response.result;List<dynamic> chats=[];try{chats=List<dynamic>.from(updates.chats as List);}catch(_){}for(final chat in chats){if(chat is t.Channel&&chat.accessHash!=null){port.send({'type':'completed','result':{'id':chat.id,'accessHash':chat.accessHash,'title':chat.title}});return;}}throw Exception('Storage channel was created, but its accessHash could not be read.');}catch(e,s){port.send({'type':'error','error':e.toString(),'stackTrace':s.toString()});}finally{try{await tc.disconnect();}catch(_){}}}

class TelegramStorageException implements Exception{final String message;final String? stackTrace;const TelegramStorageException(this.message,{this.stackTrace});@override String toString()=>message;}
class TelegramStorageFileTooLargeException extends TelegramStorageException{final int fileSize,maxSize;TelegramStorageFileTooLargeException({required this.fileSize,required this.maxSize}):super('File is too large for a single Telegram storage part.');}
