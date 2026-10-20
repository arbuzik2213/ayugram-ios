import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Аналог SendWithoutSoundOption из AyuGram Desktop.
enum SendWithoutSound { never, inGhostMode, always }

/// Регулярный фильтр сообщений (RegexFilter в ayu/data/entities.h).
class RegexFilter {
  RegexFilter({
    required this.id,
    required this.text,
    this.enabled = true,
    this.reversed = false,
    this.caseInsensitive = true,
    this.dialogId,
  });

  final String id;
  String text;
  bool enabled;
  bool reversed;
  bool caseInsensitive;
  int? dialogId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'enabled': enabled,
        'reversed': reversed,
        'caseInsensitive': caseInsensitive,
        if (dialogId != null) 'dialogId': dialogId,
      };

  factory RegexFilter.fromJson(Map<String, dynamic> j) => RegexFilter(
        id: j['id'] as String,
        text: j['text'] as String,
        enabled: j['enabled'] as bool? ?? true,
        reversed: j['reversed'] as bool? ?? false,
        caseInsensitive: j['caseInsensitive'] as bool? ?? true,
        dialogId: (j['dialogId'] as num?)?.toInt(),
      );

  RegExp? _compiled;
  RegExp? get regex {
    try {
      return _compiled ??= RegExp(text, caseSensitive: !caseInsensitive, unicode: true);
    } catch (_) {
      return null;
    }
  }

  void invalidate() => _compiled = null;
}

/// Настройки AyuGram. Набор и значения по умолчанию взяты из
/// Telegram/SourceFiles/ayu/ayu_settings.h (AyuGramDesktop).
class AyuSettings extends ChangeNotifier {
  AyuSettings._();
  static final AyuSettings instance = AyuSettings._();

  late SharedPreferences _prefs;

  // --- Режим призрака (GhostModeAccountSettings) ---
  bool sendReadMessages = true;
  bool sendOnlinePackets = true;
  bool sendUploadProgress = true;
  bool sendOfflinePacketAfterOnline = false;
  bool markReadAfterAction = true;
  bool useScheduledMessages = false;
  SendWithoutSound sendWithoutSound = SendWithoutSound.never;

  // --- Шпионские функции ---
  bool saveDeletedMessages = true;
  bool saveMessagesHistory = true;
  bool saveForBots = false;

  // --- Фильтры ---
  bool filtersEnabled = false;
  bool filtersEnabledInChats = false;
  bool hideFromBlocked = false;
  List<RegexFilter> filters = [];

  // --- Внешний вид ---
  bool semiTransparentDeletedMessages = true;
  String deletedMark = '🧹';
  String editedMark = 'изм.';
  bool showPeerId = true;
  bool showMessageSeconds = false;
  bool filterZalgo = true;
  bool disableAds = true;
  bool streamerMode = false;
  bool nightMode = true;

  // --- Подтверждения отправки ---
  bool stickerConfirmation = false;

  /// Включён ли «режим призрака» целиком: все три пакета не отправляются.
  bool get isGhostModeActive => !sendReadMessages && !sendOnlinePackets && !sendUploadProgress;

  bool get isUseScheduledMessages => isGhostModeActive && useScheduledMessages;

  bool get shouldSendWithoutSound => switch (sendWithoutSound) {
        SendWithoutSound.never => false,
        SendWithoutSound.inGhostMode => isGhostModeActive,
        SendWithoutSound.always => true,
      };

  /// Переключатель «призрака» как в шторке AyuGram: включает/выключает все пакеты разом.
  void setGhostModeEnabled(bool enabled) {
    sendReadMessages = !enabled;
    sendOnlinePackets = !enabled;
    sendUploadProgress = !enabled;
    sendOfflinePacketAfterOnline = enabled;
    save();
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('ayu_settings');
    if (raw != null) {
      try {
        _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  void save() {
    _prefs.setString('ayu_settings', jsonEncode(_toJson()));
    notifyListeners();
  }

  Map<String, dynamic> _toJson() => {
        'sendReadMessages': sendReadMessages,
        'sendOnlinePackets': sendOnlinePackets,
        'sendUploadProgress': sendUploadProgress,
        'sendOfflinePacketAfterOnline': sendOfflinePacketAfterOnline,
        'markReadAfterAction': markReadAfterAction,
        'useScheduledMessages': useScheduledMessages,
        'sendWithoutSound': sendWithoutSound.index,
        'saveDeletedMessages': saveDeletedMessages,
        'saveMessagesHistory': saveMessagesHistory,
        'saveForBots': saveForBots,
        'filtersEnabled': filtersEnabled,
        'filtersEnabledInChats': filtersEnabledInChats,
        'hideFromBlocked': hideFromBlocked,
        'filters': filters.map((f) => f.toJson()).toList(),
        'semiTransparentDeletedMessages': semiTransparentDeletedMessages,
        'deletedMark': deletedMark,
        'editedMark': editedMark,
        'showPeerId': showPeerId,
        'showMessageSeconds': showMessageSeconds,
        'filterZalgo': filterZalgo,
        'disableAds': disableAds,
        'streamerMode': streamerMode,
        'nightMode': nightMode,
        'stickerConfirmation': stickerConfirmation,
      };

  void _fromJson(Map<String, dynamic> j) {
    T v<T>(String k, T def) => j[k] is T ? j[k] as T : def;
    sendReadMessages = v('sendReadMessages', sendReadMessages);
    sendOnlinePackets = v('sendOnlinePackets', sendOnlinePackets);
    sendUploadProgress = v('sendUploadProgress', sendUploadProgress);
    sendOfflinePacketAfterOnline = v('sendOfflinePacketAfterOnline', sendOfflinePacketAfterOnline);
    markReadAfterAction = v('markReadAfterAction', markReadAfterAction);
    useScheduledMessages = v('useScheduledMessages', useScheduledMessages);
    final sws = v<int>('sendWithoutSound', 0);
    sendWithoutSound = SendWithoutSound.values[sws.clamp(0, SendWithoutSound.values.length - 1)];
    saveDeletedMessages = v('saveDeletedMessages', saveDeletedMessages);
    saveMessagesHistory = v('saveMessagesHistory', saveMessagesHistory);
    saveForBots = v('saveForBots', saveForBots);
    filtersEnabled = v('filtersEnabled', filtersEnabled);
    filtersEnabledInChats = v('filtersEnabledInChats', filtersEnabledInChats);
    hideFromBlocked = v('hideFromBlocked', hideFromBlocked);
    final fl = j['filters'];
    if (fl is List) {
      filters = fl.whereType<Map<String, dynamic>>().map(RegexFilter.fromJson).toList();
    }
    semiTransparentDeletedMessages = v('semiTransparentDeletedMessages', semiTransparentDeletedMessages);
    deletedMark = v('deletedMark', deletedMark);
    editedMark = v('editedMark', editedMark);
    showPeerId = v('showPeerId', showPeerId);
    showMessageSeconds = v('showMessageSeconds', showMessageSeconds);
    filterZalgo = v('filterZalgo', filterZalgo);
    disableAds = v('disableAds', disableAds);
    streamerMode = v('streamerMode', streamerMode);
    nightMode = v('nightMode', nightMode);
    stickerConfirmation = v('stickerConfirmation', stickerConfirmation);
  }

  // --- API-ключи Telegram (my.telegram.org) ---
  static const _envApiId = String.fromEnvironment('TG_API_ID');
  static const _envApiHash = String.fromEnvironment('TG_API_HASH');

  int? get apiId => int.tryParse(_envApiId) ?? _prefs.getInt('api_id');
  String? get apiHash => _envApiHash.isNotEmpty ? _envApiHash : _prefs.getString('api_hash');

  Future<void> setApiKeys(int id, String hash) async {
    await _prefs.setInt('api_id', id);
    await _prefs.setString('api_hash', hash);
  }
}
