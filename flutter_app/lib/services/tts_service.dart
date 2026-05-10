import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

const String _baseUrl = 'http://localhost:8000';

class VoiceOption {
  final String id;
  final String label;
  const VoiceOption({required this.id, required this.label});
}

class EngineInfo {
  final String id;
  final String label;
  final bool offline;
  final String quality;
  final List<VoiceOption> voices;
  final double speedMin;
  final double speedMax;
  final double speedDefault;

  const EngineInfo({
    required this.id,
    required this.label,
    required this.offline,
    required this.quality,
    required this.voices,
    required this.speedMin,
    required this.speedMax,
    required this.speedDefault,
  });
}

class GenerateResult {
  final String fileId;
  final String filename;
  final String engine;
  final String voice;
  final int chars;
  final double durationSeconds;

  const GenerateResult({
    required this.fileId,
    required this.filename,
    required this.engine,
    required this.voice,
    required this.chars,
    required this.durationSeconds,
  });

  String get audioUrl => '$_baseUrl/api/audio/$filename';

  String get durationLabel {
    final mins = (durationSeconds ~/ 60);
    final secs = (durationSeconds % 60).toInt();
    if (mins > 0) return '${mins}m ${secs}s';
    return '${durationSeconds.toStringAsFixed(1)}s';
  }
}

class TTSService {
  static Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<EngineInfo>> getEngines() async {
    final res = await http
        .get(Uri.parse('$_baseUrl/api/voices'))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) throw Exception('Error cargando voces');

    final data = jsonDecode(res.body)['engines'] as Map<String, dynamic>;

    return data.entries.map((e) {
      final eng = e.value as Map<String, dynamic>;
      final voicesList = (eng['voices'] as List)
          .map((v) => VoiceOption(id: v['id'], label: v['label']))
          .toList();

      return EngineInfo(
        id: e.key,
        label: eng['label'],
        offline: eng['offline'],
        quality: eng['quality'],
        voices: voicesList,
        speedMin: (eng['speed_min'] as num).toDouble(),
        speedMax: (eng['speed_max'] as num).toDouble(),
        speedDefault: (eng['speed_default'] as num).toDouble(),
      );
    }).toList();
  }

  static Future<GenerateResult> generate({
    required String text,
    required String engine,
    required String voice,
    required double speed,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/api/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'engine': engine,
            'voice': voice,
            'speed': speed,
          }),
        )
        .timeout(const Duration(minutes: 10));

    if (res.statusCode != 200) {
      final err = jsonDecode(res.body)['detail'] ?? 'Error desconocido';
      throw Exception(err);
    }

    final data = jsonDecode(res.body);
    return GenerateResult(
      fileId: data['file_id'],
      filename: data['filename'],
      engine: data['engine'],
      voice: data['voice'],
      chars: data['chars'],
      durationSeconds: (data['duration_seconds'] as num).toDouble(),
    );
  }

  static Future<Uint8List> downloadAudio(String audioUrl) async {
    final res = await http
        .get(Uri.parse(audioUrl))
        .timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) throw Exception('Error descargando audio');
    return res.bodyBytes;
  }
}
