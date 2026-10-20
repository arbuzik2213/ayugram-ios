import '../td/td_client.dart';
import 'ayu_settings.dart';

/// Порт ayu/features/filters/filters_controller.cpp.
class AyuFilters {
  static final _zalgo = RegExp(r'[̀-ͯ҃-҉᪰-᫿᷀-᷿⃐-⃿︠-︯]{2,}');

  /// Убирает «залго» (нагромождение комбинируемых диакритических знаков).
  static String stripZalgo(String s) => s.replaceAll(_zalgo, '');

  /// Включены ли фильтры для этого чата: по умолчанию только в каналах,
  /// в остальных чатах — если включён filtersEnabledInChats.
  static bool isEnabled(TdObject chat) {
    final s = AyuSettings.instance;
    if (!s.filtersEnabled) return false;
    if (s.filtersEnabledInChats) return true;
    final type = chat['type'] as TdObject?;
    return type?['@type'] == 'chatTypeSupergroup' && type?['is_channel'] == true;
  }

  static bool _matches(RegexFilter f, String text) {
    final r = f.regex;
    if (r == null) return false;
    final match = r.hasMatch(text);
    return f.reversed ? !match : match;
  }

  /// true — сообщение должно быть скрыто.
  static bool isFiltered({
    required TdObject chat,
    required TdObject message,
    required String text,
    required bool Function(int userId) isBlockedUser,
  }) {
    final s = AyuSettings.instance;
    if (!s.filtersEnabled) return false;
    if (message['is_outgoing'] == true) return false;

    final chatId = chat['id'] as int;
    if (s.hideFromBlocked) {
      final sender = message['sender_id'] as TdObject?;
      final senderUser = sender?['@type'] == 'messageSenderUser' ? sender!['user_id'] as int : null;
      // В личке с заблокированным сообщения не скрываем, как и в оригинале.
      if (senderUser != null && senderUser != chatId && isBlockedUser(senderUser)) return true;
      final via = message['via_bot_user_id'] as int? ?? 0;
      if (via != 0 && isBlockedUser(via)) return true;
      final origin = (message['forward_info'] as TdObject?)?['origin'] as TdObject?;
      if (origin?['@type'] == 'messageOriginUser' && isBlockedUser(origin!['sender_user_id'] as int)) {
        return true;
      }
    }

    if (!isEnabled(chat) || text.isEmpty) return false;

    for (final f in s.filters) {
      if (!f.enabled) continue;
      if (f.dialogId != null && f.dialogId != chatId) continue;
      if (_matches(f, text)) return true;
    }
    return false;
  }
}
