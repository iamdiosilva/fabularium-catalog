import 'dart:async';
import 'dart:typed_data';

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

  static const int _maxPhoneMigrations =
      3;

  final TelegramClient _telegramClient =
      TelegramClient.instance;

  t.AuthSentCode? _authSentCode;

  t.AccountPassword? _accountPassword;

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
          await _telegramClient.disconnect();

          _clearAuthTemporaryState();

          _setState(
            TelegramAuthState.authenticated,
          );

          return;
        }

        await _telegramClient.deleteSession();

        await _telegramClient.disconnect();

        _clearAuthTemporaryState();

        // The old implementation returned "disconnected" here, but the phone
        // form needs an active MTProto client in order to call auth.sendCode.
        //
        // Build a fresh unauthenticated client before exposing the phone step.
        await _telegramClient.connect();

        _setState(
          TelegramAuthState.phoneRequired,
        );

        return;
      }

      _clearAuthTemporaryState();

      _setState(
        TelegramAuthState.phoneRequired,
      );
    } catch (error) {
      try {
        await _telegramClient.disconnect();
      } catch (_) {}

      _setError(
        error,
      );
    }
  }

  Future<bool> _validateSession(
    tg.Client client,
  ) async {
    try {
      final response =
          await client.users.getUsers(
        id:
            const <t.InputUserBase>[
          t.InputUserSelf(),
        ],
      );

      final error =
          response.error;

      if (error != null) {
        if (_isInvalidSessionError(
          error.errorMessage,
        )) {
          return false;
        }

        throw Exception(
          error.errorMessage,
        );
      }

      return response.result !=
          null;
    } catch (error) {
      if (_isInvalidSessionError(
        error.toString(),
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
    final normalizedPhone =
        phoneNumber.trim();

    if (normalizedPhone.isEmpty) {
      _setError(
        'Informe o número de telefone.',
      );

      return;
    }

    _phoneNumber =
        normalizedPhone;

    _authSentCode =
        null;

    _accountPassword =
        null;

    try {
      await _sendCodeOnCurrentDc(
        phoneNumber:
            normalizedPhone,
        migrationAttempt:
            0,
      );
    } catch (error) {
      _setError(
        error,
      );
    }
  }

  Future<void> _sendCodeOnCurrentDc({
    required String phoneNumber,
    required int migrationAttempt,
  }) async {
    final client =
        _telegramClient.client ??
            await _telegramClient.connect();

    final response =
        await client.auth.sendCode(
      apiId:
          TelegramConfig.apiId,
      apiHash:
          TelegramConfig.apiHash,
      phoneNumber:
          phoneNumber,
      settings:
          const t.CodeSettings(
        allowFlashcall:
            false,
        currentNumber:
            true,
        allowAppHash:
            false,
        allowMissedCall:
            false,
        allowFirebase:
            false,
        unknownNumber:
            false,
      ),
    );

    final error =
        response.error;

    if (error != null) {
      final migrated =
          await _tryHandlePhoneMigration(
        errorMessage:
            error.errorMessage,
        phoneNumber:
            phoneNumber,
        migrationAttempt:
            migrationAttempt,
      );

      if (migrated) {
        return;
      }

      _setError(
        error.errorMessage,
      );

      return;
    }

    final result =
        response.result;

    if (result is! t.AuthSentCode) {
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
  }

  Future<bool> _tryHandlePhoneMigration({
    required String errorMessage,
    required String phoneNumber,
    required int migrationAttempt,
  }) async {
    final match =
        RegExp(
      r'^PHONE_MIGRATE_(\d+)$',
    ).firstMatch(
      errorMessage,
    );

    if (match ==
        null) {
      return false;
    }

    if (migrationAttempt >=
        _maxPhoneMigrations) {
      _setError(
        'Telegram requested too many data-center migrations.',
      );

      return true;
    }

    final dcId =
        int.tryParse(
      match.group(
            1,
          ) ??
          '',
    );

    if (dcId ==
        null) {
      _setError(
        errorMessage,
      );

      return true;
    }

    final dc =
        _telegramClient.findDataCenter(
      dcId,
    );

    if (dc ==
        null) {
      _setError(
        'Telegram requested DC $dcId, but the endpoint is unavailable.',
      );

      return true;
    }

    // This is especially common when switching Telegram accounts:
    // the second phone number may belong to a different authorization DC.
    //
    // The previous implementation changed DC and returned to phoneRequired,
    // forcing the user to press Send Code again with no explanation.
    //
    // We now migrate and transparently retry the same auth.sendCode.
    await _telegramClient.changeDataCenter(
      dc,
    );

    await _telegramClient.connect();

    await _sendCodeOnCurrentDc(
      phoneNumber:
          phoneNumber,
      migrationAttempt:
          migrationAttempt + 1,
    );

    return true;
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

    if (client ==
            null ||
        authSentCode ==
            null ||
        phoneNumber ==
            null) {
      _setError(
        'A autenticação não foi iniciada corretamente.',
      );

      return;
    }

    final normalizedCode =
        code.trim();

    if (normalizedCode.isEmpty) {
      _setError(
        'Informe o código de verificação.',
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
            normalizedCode,
      );

      if (response.error ==
          null) {
        await _completeAuthentication();

        return;
      }

      if (response
              .error!
              .errorMessage ==
          'SESSION_PASSWORD_NEEDED') {
        await _loadPassword();

        return;
      }

      _setError(
        response
            .error!
            .errorMessage,
      );
    } catch (error) {
      _setError(
        error,
      );
    }
  }

  Future<void> _loadPassword() async {
    final client =
        _telegramClient.client;

    if (client ==
        null) {
      _setError(
        'Cliente Telegram não está conectado.',
      );

      return;
    }

    try {
      final response =
          await client.account.getPassword();

      if (response.error !=
          null) {
        _setError(
          response
              .error!
              .errorMessage,
        );

        return;
      }

      final result =
          response.result;

      if (result is! t.AccountPassword) {
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
    } catch (error) {
      _setError(
        error,
      );
    }
  }

  Future<void> checkPassword(
    String password,
  ) async {
    final client =
        _telegramClient.client;

    final accountPassword =
        _accountPassword;

    if (client ==
            null ||
        accountPassword ==
            null) {
      _setError(
        'Informações de 2FA não disponíveis.',
      );

      return;
    }

    if (password.isEmpty) {
      _setError(
        'Informe a senha de verificação em duas etapas.',
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
          await client.auth.checkPassword(
        password:
            passwordResult,
      );

      if (response.error !=
          null) {
        _setError(
          response
              .error!
              .errorMessage,
        );

        return;
      }

      await _completeAuthentication();
    } catch (error) {
      _setError(
        error,
      );
    }
  }

  Future<void> _completeAuthentication() async {
    await _telegramClient.saveSession();

    await _telegramClient.disconnect();

    _clearAuthTemporaryState();

    _setState(
      TelegramAuthState.authenticated,
    );
  }

  void _clearAuthTemporaryState() {
    _authSentCode =
        null;

    _accountPassword =
        null;

    _phoneNumber =
        null;
  }

  Future<List<TelegramMessage>> getMessages(
    TelegramGroup group, {
    int limit = 50,
    int offsetId = 0,
  }) async {
    final client =
        _telegramClient.client;

    if (client ==
        null) {
      throw StateError(
        'Cliente Telegram não está conectado.',
      );
    }

    final peer =
        _createInputPeer(
      group,
    );

    final response =
        await client.messages.getHistory(
      peer:
          peer,
      offsetId:
          offsetId,
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

    if (response.error !=
        null) {
      final errorMessage =
          response
              .error!
              .errorMessage;

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

    if (result ==
        null) {
      return <TelegramMessage>[];
    }

    final dynamic data =
        result;

    List<dynamic> rawMessages =
        <dynamic>[];

    List<dynamic> users =
        <dynamic>[];

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
            '$firstName $lastName'.trim();

        userNames[id] =
            fullName.isNotEmpty
                ? fullName
                : username.isNotEmpty
                    ? '@$username'
                    : 'User $id';
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
              rawMessage.date as DateTime?;
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

        if (text
                .trim()
                .isEmpty &&
            media ==
                null) {
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
    try {
      final dynamic fromId =
          message.fromId;

      if (fromId ==
          null) {
        return 'Unknown';
      }

      final type =
          fromId.runtimeType.toString();

      if (type ==
          'PeerUser') {
        final userId =
            fromId.userId as int;

        return userNames[userId] ??
            'User $userId';
      }

      if (type ==
              'PeerChat' ||
          type ==
              'PeerChannel') {
        return group.title;
      }
    } catch (_) {}

    return 'Unknown';
  }

  TelegramMedia? _extractMedia(
    dynamic message,
  ) {
    try {
      final dynamic media =
          message.media;

      if (media ==
          null) {
        return null;
      }

      final type =
          media.runtimeType.toString();

      if (type ==
          'MessageMediaPhoto') {
        final dynamic photo =
            media.photo;

        if (photo ==
                null ||
            photo.runtimeType
                    .toString() !=
                'Photo') {
          return null;
        }

        return _createPhotoMedia(
          photo,
        );
      }

      if (type ==
          'MessageMediaDocument') {
        final dynamic document =
            media.document;

        if (document ==
                null ||
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
        (
          a,
          b,
        ) =>
            a.area.compareTo(
          b.area,
        ),
      );

      final fullSize =
          sizes.last;

      var previewSize =
          fullSize;

      for (final size
          in sizes) {
        if (size.width >=
                640 ||
            size.height >=
                640) {
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
          document.mimeType as String;

      final Uint8List fileReference =
          Uint8List.fromList(
        List<int>.from(
          document.fileReference as List,
        ),
      );

      final attributes =
          List<dynamic>.from(
        document.attributes as List,
      );

      String? fileName;

      for (final dynamic attribute
          in attributes) {
        if (attribute.runtimeType
            .toString()
            .startsWith(
              'DocumentAttributeFilename',
            )) {
          try {
            fileName =
                attribute.fileName as String;
          } catch (_) {}

          if (fileName !=
                  null &&
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

        if (thumbsRaw !=
            null) {
          final thumbs =
              _readPhotoSizes(
            List<dynamic>.from(
              thumbsRaw as List,
            ),
          );

          if (thumbs.isNotEmpty) {
            thumbs.sort(
              (
                a,
                b,
              ) =>
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

  List<_TelegramRemotePhotoSize> _readPhotoSizes(
    List<dynamic> rawSizes,
  ) {
    final result =
        <_TelegramRemotePhotoSize>[];

    for (final dynamic raw
        in rawSizes) {
      try {
        final runtimeType =
            raw.runtimeType.toString();

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

          if (progressiveSizes.isNotEmpty) {
            size =
                progressiveSizes.last;
          }
        }

        if (type.isEmpty ||
            size <=
                0) {
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

    return extension.isEmpty
        ? 'document_$id'
        : 'document_$id.$extension';
  }

  String _extensionForMimeType(
    String mimeType,
  ) {
    switch (mimeType.toLowerCase()) {
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

    if (accessHash ==
        null) {
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

  Future<void> _invalidateSession() async {
    Object? firstError;

    try {
      await _telegramClient.deleteSession();
    } catch (error) {
      firstError ??=
          error;
    }

    try {
      await _telegramClient.disconnect();
    } catch (error) {
      firstError ??=
          error;
    } finally {
      _clearAuthTemporaryState();

      _setState(
        TelegramAuthState.disconnected,
      );
    }

    if (firstError !=
        null) {
      throw firstError;
    }
  }

  Future<void> logout() async {
    Object? firstError;

    try {
      await _telegramClient.deleteSession();
    } catch (error) {
      firstError ??=
          error;
    }

    try {
      await _telegramClient.disconnect();
    } catch (error) {
      firstError ??=
          error;
    } finally {
      // Important when switching Fabularium accounts. Even if Telegram socket
      // cleanup fails, the application must never keep the old auth flow state
      // (phone/hash/2FA or "authenticated") alive for the next account.
      _clearAuthTemporaryState();

      _setState(
        TelegramAuthState.disconnected,
      );
    }

    if (firstError !=
        null) {
      throw firstError;
    }
  }

  void _setState(
    TelegramAuthState state,
  ) {
    _state =
        state;

    _errorMessage =
        null;

    if (!_stateController.isClosed) {
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

    if (!_stateController.isClosed) {
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
