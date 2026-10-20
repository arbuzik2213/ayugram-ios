import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../td/td_client.dart';

/// Локальная база AyuGram (аналог ayu/data/ayu_database.cpp):
/// кэш последних сообщений, удалённые сообщения и история правок.
class MessageStore {
  MessageStore._();
  static final MessageStore instance = MessageStore._();

  late Database _db;

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'ayu.db'),
      version: 1,
      onCreate: (db, _) async {
        // Последняя известная версия каждого сообщения — чтобы было что показать после удаления.
        await db.execute('''
          CREATE TABLE cache (
            chat_id INTEGER NOT NULL,
            message_id INTEGER NOT NULL,
            date INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (chat_id, message_id)
          )''');
        await db.execute('CREATE INDEX cache_date ON cache(date)');
        await db.execute('''
          CREATE TABLE deleted (
            chat_id INTEGER NOT NULL,
            message_id INTEGER NOT NULL,
            date INTEGER NOT NULL,
            deleted_at INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (chat_id, message_id)
          )''');
        await db.execute('''
          CREATE TABLE edited (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id INTEGER NOT NULL,
            message_id INTEGER NOT NULL,
            edit_date INTEGER NOT NULL,
            json TEXT NOT NULL
          )''');
        await db.execute('CREATE INDEX edited_msg ON edited(chat_id, message_id)');
      },
    );
    // Кэш живых сообщений держим не дольше 14 дней.
    final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 14 * 86400;
    await _db.delete('cache', where: 'date < ?', whereArgs: [cutoff]);
  }

  Future<void> cacheMessages(Iterable<TdObject> messages) async {
    final batch = _db.batch();
    for (final m in messages) {
      if (m['sending_state'] != null) continue;
      batch.insert(
        'cache',
        {
          'chat_id': m['chat_id'],
          'message_id': m['id'],
          'date': m['date'],
          'json': jsonEncode(m),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<TdObject?> cached(int chatId, int messageId) async {
    final rows = await _db.query('cache',
        columns: ['json'], where: 'chat_id = ? AND message_id = ?', whereArgs: [chatId, messageId]);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json'] as String) as TdObject;
  }

  /// Переносит сообщения из кэша в «удалённые». Возвращает сохранённые.
  Future<List<TdObject>> markDeleted(int chatId, List<int> ids, {Map<int, TdObject>? inMemory}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final saved = <TdObject>[];
    for (final id in ids) {
      final m = inMemory?[id] ?? await cached(chatId, id);
      if (m == null) continue;
      saved.add(m);
      await _db.insert(
        'deleted',
        {'chat_id': chatId, 'message_id': id, 'date': m['date'], 'deleted_at': now, 'json': jsonEncode(m)},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    return saved;
  }

  Future<Map<int, int>> deletedAt(int chatId) async {
    final rows = await _db.query('deleted', columns: ['message_id', 'deleted_at'], where: 'chat_id = ?', whereArgs: [chatId]);
    return {for (final r in rows) r['message_id'] as int: r['deleted_at'] as int};
  }

  /// Удалённые сообщения чата в диапазоне id (включительно), новые сверху.
  Future<List<TdObject>> deletedInRange(int chatId, int fromId, int toId) async {
    final rows = await _db.query('deleted',
        columns: ['json'],
        where: 'chat_id = ? AND message_id >= ? AND message_id <= ?',
        whereArgs: [chatId, fromId, toId],
        orderBy: 'message_id DESC');
    return [for (final r in rows) jsonDecode(r['json'] as String) as TdObject];
  }

  Future<List<TdObject>> allDeleted(int chatId) async {
    final rows = await _db.query('deleted',
        columns: ['json'], where: 'chat_id = ?', whereArgs: [chatId], orderBy: 'message_id DESC');
    return [for (final r in rows) jsonDecode(r['json'] as String) as TdObject];
  }

  Future<void> saveEdit(TdObject oldMessage) async {
    await _db.insert('edited', {
      'chat_id': oldMessage['chat_id'],
      'message_id': oldMessage['id'],
      'edit_date': (oldMessage['edit_date'] as int?) != 0 ? oldMessage['edit_date'] : oldMessage['date'],
      'json': jsonEncode(oldMessage),
    });
  }

  Future<List<TdObject>> edits(int chatId, int messageId) async {
    final rows = await _db.query('edited',
        columns: ['json'],
        where: 'chat_id = ? AND message_id = ?',
        whereArgs: [chatId, messageId],
        orderBy: 'id ASC');
    return [for (final r in rows) jsonDecode(r['json'] as String) as TdObject];
  }

  Future<Set<int>> editedIds(int chatId) async {
    final rows = await _db.rawQuery('SELECT DISTINCT message_id FROM edited WHERE chat_id = ?', [chatId]);
    return {for (final r in rows) r['message_id'] as int};
  }

  Future<void> clearAll() async {
    await _db.delete('deleted');
    await _db.delete('edited');
  }

  Future<(int, int)> stats() async {
    final d = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM deleted')) ?? 0;
    final e = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM edited')) ?? 0;
    return (d, e);
  }
}
