import '../ayu/ayu_settings.dart';
import '../ayu/filters.dart';
import '../td/td_client.dart';

String _two(int v) => v.toString().padLeft(2, '0');

DateTime unix(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);

/// Время сообщения; с секундами, если включено showMessageSeconds.
String messageTime(int date) {
  final d = unix(date);
  final base = '${_two(d.hour)}:${_two(d.minute)}';
  return AyuSettings.instance.showMessageSeconds ? '$base:${_two(d.second)}' : base;
}

/// Время в списке чатов: сегодня — часы, иначе дата.
String chatListTime(int date) {
  final d = unix(date);
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '${_two(d.hour)}:${_two(d.minute)}';
  }
  if (now.difference(d).inDays < 7) {
    return const ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'][d.weekday - 1];
  }
  return '${_two(d.day)}.${_two(d.month)}.${d.year % 100}';
}

String fullDate(int date) {
  final d = unix(date);
  return '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

String dayHeader(int date) {
  const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
  final d = unix(date);
  final now = DateTime.now();
  final s = '${d.day} ${months[d.month - 1]}';
  return d.year == now.year ? s : '$s ${d.year}';
}

String duration(int seconds) => '${seconds ~/ 60}:${_two(seconds % 60)}';

String _clean(String s) => AyuSettings.instance.filterZalgo ? AyuFilters.stripZalgo(s) : s;

/// Текст (или подпись) сообщения.
String contentText(TdObject? content) {
  if (content == null) return '';
  final t = content['text'] ?? content['caption'];
  if (t is Map) return _clean(t['text'] as String? ?? '');
  return '';
}

/// Краткое описание сообщения для списка чатов и ответов.
String contentPreview(TdObject? content) {
  if (content == null) return '';
  final text = contentText(content);
  String withText(String label) => text.isEmpty ? label : '$label $text';
  return switch (content['@type']) {
    'messageText' => text,
    'messagePhoto' => withText('🖼 Фото'),
    'messageVideo' => withText('📹 Видео'),
    'messageAnimation' => withText('GIF'),
    'messageVoiceNote' => withText('🎤 Голосовое'),
    'messageVideoNote' => '⏺ Видеосообщение',
    'messageAudio' => withText('🎵 ${(content['audio'] as TdObject?)?['title'] ?? 'Аудио'}'),
    'messageDocument' => withText('📎 ${(content['document'] as TdObject?)?['file_name'] ?? 'Файл'}'),
    'messageSticker' => '${(content['sticker'] as TdObject?)?['emoji'] ?? ''} Стикер',
    'messageLocation' => '📍 Геопозиция',
    'messageContact' => '👤 Контакт',
    'messagePoll' => '📊 ${((content['poll'] as TdObject?)?['question'] as TdObject?)?['text'] ?? 'Опрос'}',
    'messageCall' => '📞 Звонок',
    'messagePinMessage' => '📌 Закреплено сообщение',
    'messageChatAddMembers' => 'Добавлены участники',
    'messageChatJoinByLink' => 'Вступил(а) по ссылке',
    'messageChatDeleteMember' => 'Участник покинул чат',
    'messageChatChangeTitle' => 'Название изменено',
    'messageChatChangePhoto' => 'Фото чата изменено',
    'messageBasicGroupChatCreate' || 'messageSupergroupChatCreate' => 'Чат создан',
    'messageContactRegistered' => 'Присоединился(ась) к Telegram',
    'messageStory' => 'История',
    'messageDice' => (content['emoji'] as String?) ?? '🎲',
    'messageGiftedPremium' || 'messageGift' => '🎁 Подарок',
    _ => 'Сообщение',
  };
}

bool isServiceMessage(TdObject? content) {
  const normal = {
    'messageText', 'messagePhoto', 'messageVideo', 'messageAnimation', 'messageVoiceNote',
    'messageVideoNote', 'messageAudio', 'messageDocument', 'messageSticker', 'messageLocation',
    'messageContact', 'messagePoll', 'messageDice', 'messageVenue', 'messageStory', 'messageGame',
    'messageInvoice', 'messageUnsupported', 'messageAnimatedEmoji',
  };
  return content != null && !normal.contains(content['@type']);
}

/// Статус пользователя в шапке чата.
String userStatus(TdObject? user) {
  final status = user?['status'] as TdObject?;
  if ((user?['type'] as TdObject?)?['@type'] == 'userTypeBot') return 'бот';
  return switch (status?['@type']) {
    'userStatusOnline' => 'в сети',
    'userStatusOffline' => 'был(а) ${fullDate(status!['was_online'] as int)}',
    'userStatusRecently' => 'был(а) недавно',
    'userStatusLastWeek' => 'был(а) на этой неделе',
    'userStatusLastMonth' => 'был(а) в этом месяце',
    _ => 'был(а) давно',
  };
}

/// ID чата в формате Bot API (как showPeerId = BotApi в AyuGram).
String peerIdLabel(TdObject chat) => 'ID: ${chat['id']}';
