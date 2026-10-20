import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ogg_opus_player/ogg_opus_player.dart';

import '../td/td_client.dart';
import '../td/td_service.dart';
import 'format.dart';

/// Волна голосового: 5-битные значения подряд (как documentWaveformDecode в Telegram).
class Waveform {
  static List<int> decode(String? base64) {
    if (base64 == null || base64.isEmpty) return const [];
    final Uint8List bytes;
    try {
      bytes = base64Decode(base64);
    } on FormatException {
      return const [];
    }
    final count = bytes.length * 8 ~/ 5;
    final out = <int>[];
    for (var i = 0; i < count; i++) {
      final bit = i * 5;
      final byte = bit >> 3;
      final shift = bit & 7;
      final lo = bytes[byte];
      final hi = byte + 1 < bytes.length ? bytes[byte + 1] : 0;
      out.add(((lo | (hi << 8)) >> shift) & 31);
    }
    return out;
  }

  /// Сжимает сэмплы записи (0..255 и т.п.) в 63 значения по 5 бит → base64.
  static String encode(List<int> samples) {
    const n = 63;
    if (samples.isEmpty) return '';
    final peak = samples.reduce(max).clamp(1, 1 << 30);
    final values = List<int>.generate(n, (i) {
      final from = i * samples.length ~/ n;
      final to = max(from + 1, (i + 1) * samples.length ~/ n);
      var m = 0;
      for (var j = from; j < to && j < samples.length; j++) {
        m = max(m, samples[j]);
      }
      return (m * 31 / peak).round().clamp(0, 31);
    });
    final bytes = Uint8List((n * 5 + 7) ~/ 8 + 1);
    for (var i = 0; i < n; i++) {
      final bit = i * 5;
      final byte = bit >> 3;
      final shift = bit & 7;
      final v = values[i] << shift;
      bytes[byte] |= v & 0xff;
      if (byte + 1 < bytes.length) bytes[byte + 1] |= (v >> 8) & 0xff;
    }
    return base64Encode(bytes.sublist(0, (n * 5 + 7) ~/ 8));
  }
}

/// Одновременно играет только одно голосовое.
class VoicePlayback {
  VoicePlayback._();
  static final instance = VoicePlayback._();

  OggOpusPlayer? _player;
  final current = ValueNotifier<int?>(null); // file id
  final position = ValueNotifier<double>(0);
  final playing = ValueNotifier<bool>(false);
  Timer? _timer;

  Future<void> toggle(int fileId, String path) async {
    if (current.value == fileId && _player != null) {
      if (playing.value) {
        _player!.pause();
        playing.value = false;
      } else {
        _player!.play();
        playing.value = true;
      }
      return;
    }
    stop();
    final p = OggOpusPlayer(path);
    _player = p;
    current.value = fileId;
    position.value = 0;
    p.state.addListener(() {
      final s = p.state.value;
      if (s == PlayerState.ended || s == PlayerState.error) {
        if (identical(_player, p)) stop();
      }
    });
    p.play();
    playing.value = true;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (identical(_player, p)) position.value = p.currentPosition;
    });
  }

  void stop() {
    _timer?.cancel();
    _player?.dispose();
    _player = null;
    current.value = null;
    playing.value = false;
    position.value = 0;
  }
}

/// Голосовое сообщение: кнопка, волна, длительность.
class VoiceNoteView extends StatelessWidget {
  const VoiceNoteView({super.key, required this.voice, required this.accent, required this.inactive, required this.timeColor});
  final TdObject voice; // voiceNote
  final Color accent;
  final Color inactive;
  final Color timeColor;

  @override
  Widget build(BuildContext context) {
    final file = voice['voice'] as TdObject;
    final id = file['id'] as int;
    final dur = voice['duration'] as int? ?? 0;
    final wave = Waveform.decode(voice['waveform'] as String?);
    final pb = VoicePlayback.instance;
    final svc = TdService.instance;
    final fileState = svc.fileNotifier(id);
    if ((fileState.value['local'] as TdObject?) == null) fileState.value = file;

    return ListenableBuilder(
      listenable: Listenable.merge([pb.current, pb.position, pb.playing, fileState]),
      builder: (context, _) {
        final local = fileState.value['local'] as TdObject?;
        final ready = local?['is_downloading_completed'] == true;
        final downloading = local?['is_downloading_active'] == true;
        final mine = pb.current.value == id;
        final isPlaying = mine && pb.playing.value;
        final progress = mine && dur > 0 ? (pb.position.value / dur).clamp(0.0, 1.0) : 0.0;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () {
              if (ready) {
                pb.toggle(id, local!['path'] as String);
              } else {
                svc.file(file);
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: !ready && downloading
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(!ready ? Icons.arrow_downward_rounded : isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 150,
              height: 26,
              child: CustomPaint(painter: _WavePainter(wave, progress, accent, inactive)),
            ),
            const SizedBox(height: 2),
            Text(mine ? duration(pb.position.value.floor()) : duration(dur), style: TextStyle(fontSize: 13, color: timeColor)),
          ]),
        ]);
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.wave, this.progress, this.active, this.inactive);
  final List<int> wave;
  final double progress;
  final Color active, inactive;

  @override
  void paint(Canvas canvas, Size size) {
    const bar = 2.5, gap = 1.6;
    final count = (size.width / (bar + gap)).floor();
    final values = List<double>.generate(count, (i) {
      if (wave.isEmpty) return 0.15;
      return wave[i * wave.length ~/ count] / 31.0;
    });
    for (var i = 0; i < count; i++) {
      final h = max(2.5, values[i] * size.height);
      final x = i * (bar + gap);
      final paint = Paint()..color = (i / count) <= progress && progress > 0 ? active : inactive;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h, bar, h), const Radius.circular(1.2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress || old.wave != wave;
}
