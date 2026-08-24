import 'dart:async';

import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;

import '../config/telegram_config.dart';
import '../models/telegram_group.dart';
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

  TelegramAuthState get state => _state;

  String? get errorMessage => _errorMessage;

  bool get isAuthenticated =>
      _state == TelegramAuthState.authenticated;

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

        throw Exception(message);
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
        TelegramAuthState
            .passwordRequired,
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
      offsetId: 0,
      offsetPeer:
          const t.InputPeerEmpty(),
      limit: 100,
      hash: 0,
    );

    if (response.error != null) {
      throw Exception(
        response.error!.errorMessage,
      );
    }

    final result =
        response.result;

    if (result == null) {
      return [];
    }

    List<dynamic> chats;

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
          chat.runtimeType
              .toString();

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

    final t.InputPeerBase peer =
        _createInputPeer(
      group,
    );

    final response =
        await client.messages
            .getHistory(
      peer: peer,
      offsetId: 0,
      offsetDate:
          DateTime.fromMillisecondsSinceEpoch(
        0,
      ),
      addOffset: 0,
      limit: limit,
      maxId: 0,
      minId: 0,
      hash: 0,
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
        final int id =
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

    for (final dynamic message
        in rawMessages) {
      if (message.runtimeType
              .toString() !=
          'Message') {
        continue;
      }

      try {
        final int id =
            message.id as int;

        String text =
            '';

        try {
          text =
              message.message ??
                  '';
        } catch (_) {}

        if (text.trim().isEmpty) {
          text =
              '[Media or service message]';
        }

        DateTime? date;

        try {
          date =
              message.date
                  as DateTime?;
        } catch (_) {}

        String sender =
            'Unknown';

        try {
          final dynamic fromId =
              message.fromId;

          if (fromId != null) {
            final type =
                fromId.runtimeType
                    .toString();

            if (type ==
                'PeerUser') {
              final int userId =
                  fromId.userId
                      as int;

              sender =
                  userNames[
                          userId] ??
                      'User $userId';
            } else if (type ==
                'PeerChat') {
              sender =
                  'Group';
            } else if (type ==
                'PeerChannel') {
              sender =
                  group.title;
            }
          }
        } catch (_) {}

        messages.add(
          TelegramMessage(
            id: id,
            text: text,
            sender: sender,
            date: date,
          ),
        );
      } catch (_) {}
    }

    return messages;
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
            TelegramAuthState
                .phoneRequired,
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
    await _stateController
        .close();
  }
}