import 'package:flutter/services.dart';

import '../td/td_service.dart';

/// Страна из assets/countries.txt (формат Telegram Android: код;ISO;название;маска).
class Country {
  Country(this.code, this.iso, this.name, this.mask);
  final String code;
  final String iso;
  String name;
  final String? mask;

  /// Флаг-эмодзи из ISO-кода.
  String get flag {
    if (iso.length != 2 || iso == 'GO' || iso == 'FT') return '🌐';
    return String.fromCharCodes(iso.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41));
  }

  /// Подсказка в поле номера: «XX XXX XX XX» → «-- --- -- --».
  String get hint => (mask ?? 'XXX XXX XXXX').replaceAll('X', '-');

  /// Форматирует цифры по маске, как PhoneFormat в Telegram.
  String format(String digits) {
    final m = mask;
    if (m == null) return digits;
    final b = StringBuffer();
    var i = 0;
    for (final ch in m.split('')) {
      if (i >= digits.length) break;
      if (ch == 'X') {
        b.write(digits[i++]);
      } else {
        b.write(ch);
      }
    }
    if (i < digits.length) b.write(digits.substring(i));
    return b.toString();
  }
}

class Countries {
  Countries._();
  static List<Country> list = [];
  static bool _localized = false;

  static Future<void> load() async {
    if (list.isNotEmpty) return;
    final raw = await rootBundle.loadString('assets/countries.txt');
    final seen = <String>{};
    for (final line in raw.split('\n')) {
      final p = line.trim().split(';');
      if (p.length < 3 || !seen.add('${p[0]}${p[1]}')) continue;
      list.add(Country(p[0], p[1], p[2], p.length > 3 && p[3].isNotEmpty ? p[3] : null));
    }
    list.sort((a, b) => a.name.compareTo(b.name));
  }

  /// Названия на языке системы — из TDLib (getCountries), когда клиент готов.
  static Future<void> localize() async {
    if (_localized) return;
    try {
      final res = await TdService.instance.td.send({'@type': 'getCountries'});
      final byIso = {for (final c in (res['countries'] as List)) c['country_code'] as String: c['name'] as String};
      for (final c in list) {
        c.name = byIso[c.iso] ?? c.name;
      }
      list.sort((a, b) => a.name.compareTo(b.name));
      _localized = true;
    } catch (_) {}
  }

  static Country? byIso(String iso) {
    for (final c in list) {
      if (c.iso == iso.toUpperCase()) return c;
    }
    return null;
  }

  /// Самый длинный код страны, с которого начинаются цифры.
  static Country? byPrefix(String digits) {
    Country? best;
    for (final c in list) {
      if (digits.startsWith(c.code) && (best == null || c.code.length > best.code.length)) best = c;
    }
    return best;
  }

  /// Полный номер в международном виде: +380 50 123 45 67.
  static String formatFull(String digits) {
    final c = byPrefix(digits);
    if (c == null) return '+$digits';
    return '+${c.code} ${c.format(digits.substring(c.code.length))}';
  }
}
