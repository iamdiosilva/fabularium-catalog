import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;

import '../config/telegram_config.dart';
import '../models/telegram_group.dart';
import '../models/telegram_media.dart';
import '../models/telegram_message.dart';
import 'telegram_client.dart';

enum TelegramAuthState {
  disconnected,
  connecting,
  phoneRequired,
  codeRequired,
  passwordRequired,
  authenticated,
  error,
}

class TelegramService {
  TelegramService._();

  static final TelegramService instance =
      TelegramService._();

  final TelegramClient _telegramClient =
      TelegramClient.instance;

  t.AuthSentCode? _authSentCode;

  t.AccountPassword?
      _accountPassword;

  String? _phoneNumber;

  TelegramAuthState _state =
      TelegramAuthState.disconnected;

  String? _errorMessage;

  final StreamController<TelegramAuthState>
      _stateController =
      StreamController<TelegramAuthState>.broadcast();

  Stream<TelegramAuthState> get stateStream =>
      _stateController.stream;

  TelegramAuthState get state =>
      _state;

  String? get errorMessage =>
      _errorMessage;

  bool get isAuthenticated =>
      _state ==
      TelegramAuthState.authenticated;

  bool get hasSavedSession =>
      _telegramClient.hasSavedSession;

  // ============================================================
  // AUTH
  // ============================================================

  Future<void> connect() async {
    if (_state ==
        TelegramAuthState.authenticated) {
      return;
    }

    _setState(
      TelegramAuthState.connecting,
    );

    try {
      final client =
          await _telegramClient.connect();

      if (_telegramClient.hasSavedSession) {
        final valid =
            await _validateSession(
          client,
        );

        if (valid) {
          _setState(
            TelegramAuthState.authenticated,
          );

          return;
        }

        await _telegramClient
            .deleteSession();

        await _telegramClient
            .disconnect();

        _setState(
          TelegramAuthState.disconnected,
        );

        return;
      }

      _setState(
        TelegramAuthState.phoneRequired,
      );
    } catch (e) {
      _setError(e);
    }
  }

  Future<bool> _validateSession(
    tg.Client client,
  ) async {
    try {
      final response =
          await client.users.getUsers(
        id: const [
          t.InputUserSelf(),
        ],
      );

      final error =
          response.error;

      if (error != null) {
        final message =
            error.errorMessage;

        if (_isInvalidSessionError(
          message,
        )) {
          return false;
        }

        throw Exception(
          message,
        );
      }

      return response.result != null;
    } catch (e) {
      final message =
          e.toString();

      if (_isInvalidSessionError(
        message,
      )) {
        return false;
      }

      rethrow;
    }
  }

  bool _isInvalidSessionError(
    String message,
  ) {
    return message.contains(
          'AUTH_KEY_UNREGISTERED',
        ) ||
        message.contains(
          'AUTH_KEY_INVALID',
        ) ||
        message.contains(
          'SESSION_REVOKED',
        ) ||
        message.contains(
          'SESSION_EXPIRED',
        );
  }

  Future<void> sendCode(
    String phoneNumber,
  ) async {
    final client =
        _telegramClient.client;

    if (client == null) {
      _setError(
        'Cliente Telegram não está conectado.',
      );

      return;
    }

    _phoneNumber =
        phoneNumber.trim();

    if (_phoneNumber!.isEmpty) {
      _setError(
        'Informe o número de telefone.',
      );

      return;
    }

    try {
      final response =
          await client.auth.sendCode(
        apiId:
            TelegramConfig.apiId,
        apiHash:
            TelegramConfig.apiHash,
        phoneNumber:
            _phoneNumber!,
        settings:
            const t.CodeSettings(
          allowFlashcall: false,
          currentNumber: true,
          allowAppHash: false,
          allowMissedCall: false,
          allowFirebase: false,
          unknownNumber: false,
        ),
      );

      final error =
          response.error;

      if (error != null) {
        await _handleSendCodeError(
          error.errorMessage,
        );

        return;
      }

      final result =
          response.result;

      if (result
          is! t.AuthSentCode) {
        _setError(
          'Resposta inesperada do Telegram.',
        );

        return;
      }

      _authSentCode =
          result;

      _setState(
        TelegramAuthState.codeRequired,
      );
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> signIn(
    String code,
  ) async {
    final client =
        _telegramClient.client;

    final authSentCode =
        _authSentCode;

    final phoneNumber =
        _phoneNumber;

    if (client == null ||
        authSentCode == null ||
        phoneNumber == null) {
      _setError(
        'A autenticação não foi iniciada corretamente.',
      );

      return;
    }

    try {
      final response =
          await client.auth.signIn(
        phoneCodeHash:
            authSentCode.phoneCodeHash,
        phoneNumber:
            phoneNumber,
        phoneCode:
            code.trim(),
      );

      if (response.error == null) {
        await _telegramClient
            .saveSession();

        _setState(
          TelegramAuthState.authenticated,
        );

        return;
      }

      final errorMessage =
          response.error!.errorMessage;

      if (errorMessage ==
          'SESSION_PASSWORD_NEEDED') {
        await _loadPassword();

        return;
      }

      _setError(
        errorMessage,
      );
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> _loadPassword() async {
    final client =
        _telegramClient.client;

    if (client == null) {
      _setError(
        'Cliente Telegram não está conectado.',
      );

      return;
    }

    try {
      final response =
          await client.account
              .getPassword();

      if (response.error != null) {
        _setError(
          response.error!.errorMessage,
        );

        return;
      }

      final result =
          response.result;

      if (result
          is! t.AccountPassword) {
        _setError(
          'Resposta inesperada ao consultar 2FA.',
        );

        return;
      }

      _accountPassword =
          result;

      _setState(
        TelegramAuthState.passwordRequired,
      );
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> checkPassword(
    String password,
  ) async {
    final client =
        _telegramClient.client;

    final accountPassword =
        _accountPassword;

    if (client == null ||
        accountPassword == null) {
      _setError(
        'Informações de 2FA não disponíveis.',
      );

      return;
    }

    try {
      final passwordResult =
          await tg.check2FA(
        accountPassword,
        password,
      );

      final response =
          await client.auth
              .checkPassword(
        password:
            passwordResult,
      );

      if (response.error != null) {
        _setError(
          response.error!.errorMessage,
        );

        return;
      }

      await _telegramClient
          .saveSession();

      _setState(
        TelegramAuthState.authenticated,
      );
    } catch (e) {
      _setError(e);
    }
  }

  // ============================================================
  // GROUPS
  // ============================================================

  Future<List<TelegramGroup>>
      getGroups() async {
    final client =
        _telegramClient.client;

    if (client == null) {
      throw StateError(
        'Cliente Telegram não está conectado.',
      );
    }

    final response =
        await client.messages
            .getDialogs(
      excludePinned: false,
      offsetDate:
          DateTime.fromMillisecondsSinceEpoch(
        0,
      ),
      offsetId:
          0,
      offsetPeer:
          const t.InputPeerEmpty(),
      limit:
          100,
      hash:
          0,
    );

    if (response.error != null) {
      final errorMessage =
          response.error!.errorMessage;

      if (_isInvalidSessionError(
        errorMessage,
      )) {
        await _invalidateSession();
      }

      throw Exception(
        errorMessage,
      );
    }

    final result =
        response.result;

    if (result == null) {
      return [];
    }

    List<dynamic> chats =
        [];

    try {
      final dynamic dialogs =
          result;

      chats =
          List<dynamic>.from(
        dialogs.chats as List,
      );
    } catch (_) {
      return [];
    }

    final groups =
        <TelegramGroup>[];

    for (final dynamic chat
        in chats) {
      final type =
          chat.runtimeType.toString();

      if (type == 'Chat') {
        groups.add(
          TelegramGroup(
            id:
                chat.id as int,
            title:
                chat.title as String,
            accessHash:
                null,
            isChannel:
                false,
          ),
        );

        continue;
      }

      if (type == 'Channel') {
        bool megagroup =
            false;

        bool gigagroup =
            false;

        try {
          megagroup =
              chat.megagroup ==
                  true;
        } catch (_) {}

        try {
          gigagroup =
              chat.gigagroup ==
                  true;
        } catch (_) {}

        if (!megagroup &&
            !gigagroup) {
          continue;
        }

        int? accessHash;

        try {
          accessHash =
              chat.accessHash
                  as int?;
        } catch (_) {}

        groups.add(
          TelegramGroup(
            id:
                chat.id as int,
            title:
                chat.title as String,
            accessHash:
                accessHash,
            isChannel:
                true,
          ),
        );
      }
    }

    groups.sort(
      (a, b) =>
          a.title
              .toLowerCase()
              .compareTo(
                b.title
                    .toLowerCase(),
              ),
    );

    return groups;
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  Future<List<TelegramMessage>>
      getMessages(
    TelegramGroup group, {
    int limit = 50,
  }) async {
    final client =
        _telegramClient.client;

    if (client == null) {
      throw StateError(
        'Cliente Telegram não está conectado.',
      );
    }

    final peer =
        _createInputPeer(
      group,
    );

    final response =
        await client.messages
            .getHistory(
      peer:
          peer,
      offsetId:
          0,
      offsetDate:
          DateTime.fromMillisecondsSinceEpoch(
        0,
      ),
      addOffset:
          0,
      limit:
          limit,
      maxId:
          0,
      minId:
          0,
      hash:
          0,
    );

    if (response.error != null) {
      final errorMessage =
          response.error!.errorMessage;

      if (_isInvalidSessionError(
        errorMessage,
      )) {
        await _invalidateSession();
      }

      throw Exception(
        errorMessage,
      );
    }

    final result =
        response.result;

    if (result == null) {
      return [];
    }

    final dynamic data =
        result;

    List<dynamic> rawMessages =
        [];

    List<dynamic> users =
        [];

    try {
      rawMessages =
          List<dynamic>.from(
        data.messages as List,
      );
    } catch (_) {}

    try {
      users =
          List<dynamic>.from(
        data.users as List,
      );
    } catch (_) {}

    final userNames =
        <int, String>{};

    for (final dynamic user
        in users) {
      try {
        final id =
            user.id as int;

        String firstName =
            '';

        String lastName =
            '';

        String username =
            '';

        try {
          firstName =
              user.firstName ??
                  '';
        } catch (_) {}

        try {
          lastName =
              user.lastName ??
                  '';
        } catch (_) {}

        try {
          username =
              user.username ??
                  '';
        } catch (_) {}

        final fullName =
            '$firstName $lastName'
                .trim();

        if (fullName.isNotEmpty) {
          userNames[id] =
              fullName;
        } else if (username
            .isNotEmpty) {
          userNames[id] =
              '@$username';
        } else {
          userNames[id] =
              'User $id';
        }
      } catch (_) {}
    }

    final messages =
        <TelegramMessage>[];

    for (final dynamic rawMessage
        in rawMessages) {
      if (rawMessage.runtimeType
              .toString() !=
          'Message') {
        continue;
      }

      try {
        final int id =
            rawMessage.id as int;

        String text =
            '';

        try {
          text =
              rawMessage.message ??
                  '';
        } catch (_) {}

        DateTime? date;

        try {
          date =
              rawMessage.date
                  as DateTime?;
        } catch (_) {}

        final sender =
            _resolveSender(
          rawMessage,
          group,
          userNames,
        );

        final media =
            _extractMedia(
          rawMessage,
        );

        if (text.trim().isEmpty &&
            media == null) {
          text =
              '[Media or service message]';
        }

        messages.add(
          TelegramMessage(
            id:
                id,
            text:
                text,
            sender:
                sender,
            date:
                date,
            media:
                media,
          ),
        );
      } catch (_) {}
    }

    return messages;
  }

  String _resolveSender(
    dynamic message,
    TelegramGroup group,
    Map<int, String> userNames,
  ) {
    String sender =
        'Unknown';

    try {
      final dynamic fromId =
          message.fromId;

      if (fromId == null) {
        return sender;
      }

      final type =
          fromId.runtimeType
              .toString();

      if (type == 'PeerUser') {
        final userId =
            fromId.userId
                as int;

        return userNames[
                userId] ??
            'User $userId';
      }

      if (type == 'PeerChat') {
        return group.title;
      }

      if (type == 'PeerChannel') {
        return group.title;
      }
    } catch (_) {}

    return sender;
  }

  // ============================================================
  // MEDIA
  // ============================================================

  TelegramMedia? _extractMedia(
    dynamic message,
  ) {
    try {
      final dynamic media =
          message.media;

      if (media == null) {
        return null;
      }

      final mediaType =
          media.runtimeType
              .toString();

      if (mediaType ==
          'MessageMediaPhoto') {
        final dynamic photo =
            media.photo;

        if (photo == null ||
            photo.runtimeType
                    .toString() !=
                'Photo') {
          return null;
        }

        return _createPhotoMedia(
          photo,
        );
      }

      if (mediaType ==
          'MessageMediaDocument') {
        final dynamic document =
            media.document;

        if (document == null ||
            document.runtimeType
                    .toString() !=
                'Document') {
          return null;
        }

        return _createDocumentMedia(
          document,
        );
      }
    } catch (_) {}

    return null;
  }

  TelegramMedia? _createPhotoMedia(
    dynamic photo,
  ) {
    try {
      final int id =
          photo.id as int;

      final int accessHash =
          photo.accessHash as int;

      final int dcId =
          photo.dcId as int;

      final Uint8List fileReference =
          Uint8List.fromList(
        List<int>.from(
          photo.fileReference as List,
        ),
      );

      final sizes =
          _readPhotoSizes(
        photo.sizes as List,
      );

      if (sizes.isEmpty) {
        return null;
      }

      sizes.sort(
        (a, b) =>
            a.area.compareTo(
          b.area,
        ),
      );

      final fullSize =
          sizes.last;

      _TelegramRemotePhotoSize
          previewSize =
          fullSize;

      for (final size
          in sizes) {
        if (size.width >= 640 ||
            size.height >= 640) {
          previewSize =
              size;

          break;
        }
      }

      final fullLocation =
          t.InputPhotoFileLocation(
        id:
            id,
        accessHash:
            accessHash,
        fileReference:
            fileReference,
        thumbSize:
            fullSize.type,
      );

      final previewLocation =
          t.InputPhotoFileLocation(
        id:
            id,
        accessHash:
            accessHash,
        fileReference:
            fileReference,
        thumbSize:
            previewSize.type,
      );

      return TelegramMedia(
        type:
            TelegramMediaType.photo,
        cacheKey:
            'photo_${id}_${previewSize.type}',
        fileName:
            'photo_$id.jpg',
        mimeType:
            'image/jpeg',
        size:
            fullSize.size,
        dcId:
            dcId,
        location:
            fullLocation,
        previewLocation:
            previewLocation,
        previewSize:
            previewSize.size,
      );
    } catch (_) {
      return null;
    }
  }

  TelegramMedia? _createDocumentMedia(
    dynamic document,
  ) {
    try {
      final int id =
          document.id as int;

      final int accessHash =
          document.accessHash as int;

      final int dcId =
          document.dcId as int;

      final int size =
          document.size as int;

      final String mimeType =
          document.mimeType
              as String;

      final Uint8List fileReference =
          Uint8List.fromList(
        List<int>.from(
          document.fileReference
              as List,
        ),
      );

      final attributes =
          List<dynamic>.from(
        document.attributes
            as List,
      );

      String? fileName;

      for (final dynamic attribute
          in attributes) {
        final type =
            attribute.runtimeType
                .toString();

        if (type.startsWith(
          'DocumentAttributeFilename',
        )) {
          try {
            fileName =
                attribute.fileName
                    as String;
          } catch (_) {}

          if (fileName != null &&
              fileName.isNotEmpty) {
            break;
          }
        }
      }

      fileName ??=
          _buildDocumentFileName(
        id,
        mimeType,
      );

      final originalLocation =
          t.InputDocumentFileLocation(
        id:
            id,
        accessHash:
            accessHash,
        fileReference:
            fileReference,
        thumbSize:
            '',
      );

      t.InputFileLocationBase?
          previewLocation;

      int? previewSize;

      try {
        final dynamic thumbsRaw =
            document.thumbs;

        if (thumbsRaw != null) {
          final thumbs =
              _readPhotoSizes(
            List<dynamic>.from(
              thumbsRaw as List,
            ),
          );

          if (thumbs.isNotEmpty) {
            thumbs.sort(
              (a, b) =>
                  a.area.compareTo(
                b.area,
              ),
            );

            final thumb =
                thumbs.last;

            previewLocation =
                t.InputDocumentFileLocation(
              id:
                  id,
              accessHash:
                  accessHash,
              fileReference:
                  fileReference,
              thumbSize:
                  thumb.type,
            );

            previewSize =
                thumb.size;
          }
        }
      } catch (_) {}

      return TelegramMedia(
        type:
            TelegramMediaType.document,
        cacheKey:
            'document_${id}_${previewSize ?? 0}',
        fileName:
            fileName,
        mimeType:
            mimeType,
        size:
            size,
        dcId:
            dcId,
        location:
            originalLocation,
        previewLocation:
            previewLocation,
        previewSize:
            previewSize,
      );
    } catch (_) {
      return null;
    }
  }

  List<_TelegramRemotePhotoSize>
      _readPhotoSizes(
    List<dynamic> rawSizes,
  ) {
    final result =
        <_TelegramRemotePhotoSize>[];

    for (final dynamic raw
        in rawSizes) {
      try {
        final runtimeType =
            raw.runtimeType
                .toString();

        if (runtimeType !=
                'PhotoSize' &&
            runtimeType !=
                'PhotoSizeProgressive') {
          continue;
        }

        final String type =
            raw.type as String;

        final int width =
            raw.w as int;

        final int height =
            raw.h as int;

        int size =
            0;

        if (runtimeType ==
            'PhotoSize') {
          size =
              raw.size as int;
        } else {
          final progressiveSizes =
              List<int>.from(
            raw.sizes as List,
          );

          if (progressiveSizes
              .isNotEmpty) {
            size =
                progressiveSizes.last;
          }
        }

        if (type.isEmpty ||
            size <= 0) {
          continue;
        }

        result.add(
          _TelegramRemotePhotoSize(
            type:
                type,
            width:
                width,
            height:
                height,
            size:
                size,
          ),
        );
      } catch (_) {}
    }

    return result;
  }

  String _buildDocumentFileName(
    int id,
    String mimeType,
  ) {
    final extension =
        _extensionForMimeType(
      mimeType,
    );

    if (extension.isEmpty) {
      return 'document_$id';
    }

    return 'document_$id.$extension';
  }

  String _extensionForMimeType(
    String mimeType,
  ) {
    switch (mimeType
        .toLowerCase()) {
      case 'image/jpeg':
        return 'jpg';

      case 'image/png':
        return 'png';

      case 'image/webp':
        return 'webp';

      case 'image/gif':
        return 'gif';

      case 'application/pdf':
        return 'pdf';

      case 'application/zip':
        return 'zip';

      case 'application/x-rar-compressed':
      case 'application/vnd.rar':
        return 'rar';

      case 'application/x-7z-compressed':
        return '7z';

      case 'video/mp4':
        return 'mp4';

      case 'audio/mpeg':
        return 'mp3';

      default:
        return '';
    }
  }

  // ============================================================
  // DOWNLOAD
  // ============================================================

  Future<String> downloadMedia(
    TelegramMedia media, {
    required String groupTitle,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    final directory =
        await _getDownloadDirectory(
      groupTitle,
    );

    final fileName =
        _sanitizeFileName(
      media.fileName,
    );

    final destination =
        File(
      p.join(
        directory.path,
        fileName,
      ),
    );

    return _downloadLocation(
      dcId:
          media.dcId,
      location:
          media.location,
      destination:
          destination,
      expectedSize:
          media.size,
      onProgress:
          onProgress,
    );
  }

  Future<String> downloadPreview(
    TelegramMedia media,
  ) async {
    final location =
        media.previewLocation;

    if (location == null) {
      throw StateError(
        'Preview não disponível.',
      );
    }

    final directory =
        await _getCacheDirectory();

    final destination =
        File(
      p.join(
        directory.path,
        '${_sanitizeFileName(media.cacheKey)}.jpg',
      ),
    );

    return _downloadLocation(
      dcId:
          media.dcId,
      location:
          location,
      destination:
          destination,
      expectedSize:
          media.previewSize ??
              0,
    );
  }

  Future<String> _downloadLocation({
    required int dcId,
    required t.InputFileLocationBase
        location,
    required File destination,
    required int expectedSize,
    void Function(
      int received,
      int total,
    )?
        onProgress,
  }) async {
    /*
     * Agora escolhemos a conexão do DC da mídia
     * ANTES do primeiro upload.getFile().
     */
    tg.Client downloadClient =
        await _telegramClient
            .getClientForDataCenter(
      dcId,
    );

    int activeDcId =
        dcId;

    await destination.parent.create(
      recursive:
          true,
    );

    if (await destination.exists()) {
      final currentSize =
          await destination.length();

      if (expectedSize <= 0 ||
          currentSize ==
              expectedSize) {
        onProgress?.call(
          currentSize,
          expectedSize,
        );

        return destination.path;
      }
    }

    final tempFile =
        File(
      '${destination.path}.part',
    );

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    /*
     * 512 KB é aceito pelo upload.getFile
     * e evita uso desnecessário de memória.
     */
    const chunkSize =
        512 * 1024;

    int offset =
        0;

    int migrationCount =
        0;

    final output =
        await tempFile.open(
      mode:
          FileMode.write,
    );

    try {
      while (true) {
        final response =
            await downloadClient.upload
                .getFile(
          precise:
              false,
          cdnSupported:
              false,
          location:
              location,
          offset:
              offset,
          limit:
              chunkSize,
        );

        if (response.error != null) {
          final errorMessage =
              response
                  .error!
                  .errorMessage;

          /*
           * Segurança extra:
           *
           * mesmo usando document.dcId, o Telegram
           * pode informar outro DC.
           *
           * Nesse caso migramos SOMENTE o cliente
           * de download e repetimos o mesmo chunk.
           */
          final migrateDcId =
              _extractFileMigrationDc(
            errorMessage,
          );

          if (migrateDcId != null) {
            migrationCount++;

            if (migrationCount > 3) {
              throw Exception(
                'Telegram solicitou muitas '
                'migrações de Data Center '
                'durante o download.',
              );
            }

            activeDcId =
                migrateDcId;

            downloadClient =
                await _telegramClient
                    .getClientForDataCenter(
              activeDcId,
            );

            /*
             * NÃO incrementamos offset.
             *
             * Repetimos o mesmo trecho,
             * agora no DC correto.
             */
            continue;
          }

          throw Exception(
            errorMessage,
          );
        }

        final dynamic result =
            response.result;

        if (result == null) {
          throw Exception(
            'Telegram não retornou dados '
            'para o arquivo.',
          );
        }

        Uint8List bytes;

        try {
          final dynamic rawBytes =
              result.bytes;

          if (rawBytes
              is Uint8List) {
            bytes =
                rawBytes;
          } else {
            bytes =
                Uint8List.fromList(
              List<int>.from(
                rawBytes as List,
              ),
            );
          }
        } catch (_) {
          throw Exception(
            'O Telegram retornou uma '
            'resposta de arquivo não suportada.',
          );
        }

        if (bytes.isEmpty) {
          break;
        }

        await output.writeFrom(
          bytes,
        );

        offset +=
            bytes.length;

        onProgress?.call(
          offset,
          expectedSize,
        );

        if (expectedSize > 0 &&
            offset >=
                expectedSize) {
          break;
        }

        if (bytes.length <
            chunkSize) {
          break;
        }
      }
    } finally {
      await output.close();
    }

    if (expectedSize > 0) {
      final downloadedSize =
          await tempFile.length();

      if (downloadedSize <
          expectedSize) {
        try {
          await tempFile.delete();
        } catch (_) {}

        throw Exception(
          'Download incompleto. '
          'Esperado: $expectedSize bytes. '
          'Recebido: $downloadedSize bytes. '
          'Último DC: $activeDcId.',
        );
      }
    }

    if (await destination.exists()) {
      await destination.delete();
    }

    final completed =
        await tempFile.rename(
      destination.path,
    );

    return completed.path;
  }

  int? _extractFileMigrationDc(
    String errorMessage,
  ) {
    const prefixes =
        [
      'FILE_MIGRATE_',
      'NETWORK_MIGRATE_',
    ];

    for (final prefix
        in prefixes) {
      if (!errorMessage.startsWith(
        prefix,
      )) {
        continue;
      }

      return int.tryParse(
        errorMessage
            .substring(
          prefix.length,
        )
            .trim(),
      );
    }

    return null;
  }

  String? getDownloadedMediaPath(
    TelegramMedia media, {
    required String groupTitle,
  }) {
    try {
      final userProfile =
          Platform.environment[
              'USERPROFILE'];

      if (userProfile == null ||
          userProfile.isEmpty) {
        return null;
      }

      final directory =
          Directory(
        p.join(
          userProfile,
          'Downloads',
          'Fabularium',
          'Telegram',
          _sanitizeFileName(
            groupTitle,
          ),
        ),
      );

      final file =
          File(
        p.join(
          directory.path,
          _sanitizeFileName(
            media.fileName,
          ),
        ),
      );

      if (!file.existsSync()) {
        return null;
      }

      if (media.size > 0 &&
          file.lengthSync() !=
              media.size) {
        return null;
      }

      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<Directory>
      _getDownloadDirectory(
    String groupTitle,
  ) async {
    final userProfile =
        Platform.environment[
            'USERPROFILE'];

    final basePath =
        userProfile != null &&
                userProfile.isNotEmpty
            ? p.join(
                userProfile,
                'Downloads',
              )
            : Directory.current.path;

    final directory =
        Directory(
      p.join(
        basePath,
        'Fabularium',
        'Telegram',
        _sanitizeFileName(
          groupTitle,
        ),
      ),
    );

    await directory.create(
      recursive:
          true,
    );

    return directory;
  }

  Future<Directory>
      _getCacheDirectory() async {
    final localAppData =
        Platform.environment[
            'LOCALAPPDATA'];

    final basePath =
        localAppData != null &&
                localAppData.isNotEmpty
            ? localAppData
            : Directory.systemTemp.path;

    final directory =
        Directory(
      p.join(
        basePath,
        'Fabularium',
        'Telegram',
        'cache',
      ),
    );

    await directory.create(
      recursive:
          true,
    );

    return directory;
  }

  String _sanitizeFileName(
    String value,
  ) {
    String result =
        value.replaceAll(
      RegExp(
        r'[<>:"/\\|?*\x00-\x1F]',
      ),
      '_',
    );

    result =
        result.trim();

    while (result.endsWith(
          '.',
        ) ||
        result.endsWith(
          ' ',
        )) {
      result =
          result.substring(
        0,
        result.length - 1,
      );
    }

    if (result.isEmpty) {
      return 'telegram_file';
    }

    return result;
  }

  Future<void> showFileInExplorer(
    String filePath,
  ) async {
    final file =
        File(
      filePath,
    );

    if (!await file.exists()) {
      return;
    }

    if (Platform.isWindows) {
      await Process.run(
        'explorer.exe',
        [
          '/select,',
          file.path,
        ],
      );

      return;
    }

    await Process.run(
      'xdg-open',
      [
        file.parent.path,
      ],
    );
  }

  // ============================================================
  // PEER
  // ============================================================

  t.InputPeerBase _createInputPeer(
    TelegramGroup group,
  ) {
    if (!group.isChannel) {
      return t.InputPeerChat(
        chatId:
            group.id,
      );
    }

    final accessHash =
        group.accessHash;

    if (accessHash == null) {
      throw StateError(
        'O supergrupo não possui accessHash.',
      );
    }

    return t.InputPeerChannel(
      channelId:
          group.id,
      accessHash:
          accessHash,
    );
  }

  // ============================================================
  // SESSION
  // ============================================================

  Future<void>
      _invalidateSession() async {
    await _telegramClient
        .deleteSession();

    await _telegramClient
        .disconnect();

    _authSentCode =
        null;

    _accountPassword =
        null;

    _phoneNumber =
        null;

    _setState(
      TelegramAuthState.disconnected,
    );
  }

  Future<void> logout() async {
    await _telegramClient
        .deleteSession();

    await _telegramClient
        .disconnect();

    _authSentCode =
        null;

    _accountPassword =
        null;

    _phoneNumber =
        null;

    _setState(
      TelegramAuthState.disconnected,
    );
  }

  Future<void>
      _handleSendCodeError(
    String errorMessage,
  ) async {
    if (errorMessage.startsWith(
      'PHONE_MIGRATE_',
    )) {
      final dcId =
          int.tryParse(
        errorMessage
            .split('_')
            .last,
      );

      if (dcId != null) {
        final dc =
            _telegramClient
                .findDataCenter(
          dcId,
        );

        if (dc != null) {
          await _telegramClient
              .changeDataCenter(
            dc,
          );

          await _telegramClient
              .connect();

          _setState(
            TelegramAuthState.phoneRequired,
          );

          return;
        }
      }
    }

    _setError(
      errorMessage,
    );
  }

  void _setState(
    TelegramAuthState state,
  ) {
    _state =
        state;

    _errorMessage =
        null;

    if (!_stateController
        .isClosed) {
      _stateController.add(
        state,
      );
    }
  }

  void _setError(
    Object error,
  ) {
    _state =
        TelegramAuthState.error;

    _errorMessage =
        error.toString();

    if (!_stateController
        .isClosed) {
      _stateController.add(
        TelegramAuthState.error,
      );
    }
  }

  Future<void> dispose() async {
    await _stateController.close();
  }
}

class _TelegramRemotePhotoSize {
  final String type;

  final int width;

  final int height;

  final int size;

  const _TelegramRemotePhotoSize({
    required this.type,
    required this.width,
    required this.height,
    required this.size,
  });

  int get area =>
      width * height;
}