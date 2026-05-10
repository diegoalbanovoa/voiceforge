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

// ---------- Batch models ----------

enum BatchMode { reels, longVideo }

class ChunkResult {
  final int index;
  final String filename;
  final int chars;
  final double durationSeconds;
  final String status;

  const ChunkResult({
    required this.index,
    required this.filename,
    required this.chars,
    required this.durationSeconds,
    required this.status,
  });

  factory ChunkResult.fromJson(Map<String, dynamic> j) => ChunkResult(
        index: j['index'],
        filename: j['filename'],
        chars: j['chars'],
        durationSeconds: (j['duration_seconds'] as num).toDouble(),
        status: j['status'],
      );

  String get durationLabel {
    final mins = (durationSeconds ~/ 60);
    final secs = (durationSeconds % 60).toInt();
    if (mins > 0) return '${mins}m ${secs}s';
    return '${durationSeconds.toStringAsFixed(1)}s';
  }
}

class BatchJobStatus {
  final String jobId;
  final String status;
  final int totalChunks;
  final int completedChunks;
  final int failedChunks;
  final List<ChunkResult> chunks;
  final double elapsedSeconds;
  final double? etaSeconds;
  final String outputDir;

  const BatchJobStatus({
    required this.jobId,
    required this.status,
    required this.totalChunks,
    required this.completedChunks,
    required this.failedChunks,
    required this.chunks,
    required this.elapsedSeconds,
    required this.etaSeconds,
    required this.outputDir,
  });

  factory BatchJobStatus.fromJson(Map<String, dynamic> j) => BatchJobStatus(
        jobId: j['job_id'],
        status: j['status'],
        totalChunks: j['total_chunks'],
        completedChunks: j['completed_chunks'],
        failedChunks: j['failed_chunks'],
        chunks: (j['chunks'] as List)
            .map((c) => ChunkResult.fromJson(c as Map<String, dynamic>))
            .toList(),
        elapsedSeconds: (j['elapsed_seconds'] as num).toDouble(),
        etaSeconds: j['eta_seconds'] != null
            ? (j['eta_seconds'] as num).toDouble()
            : null,
        outputDir: j['output_dir'],
      );

  double get progressFraction =>
      totalChunks > 0 ? completedChunks / totalChunks : 0;

  String get etaLabel {
    if (etaSeconds == null) return 'Calculando...';
    final mins = (etaSeconds! ~/ 60).toInt();
    final secs = (etaSeconds! % 60).toInt();
    if (mins > 0) return '~${mins}m ${secs}s restantes';
    return '~${secs}s restantes';
  }

  String get elapsedLabel {
    final mins = (elapsedSeconds ~/ 60).toInt();
    final secs = (elapsedSeconds % 60).toInt();
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
  }

  bool get isDone => status == 'done' || status == 'cancelled' || status == 'error';
}

class BatchService {
  static String chunkAudioUrl(String jobId, String filename) =>
      '$_baseUrl/api/jobs/$jobId/audio/$filename';

  static Future<Map<String, dynamic>> startBatch({
    required String text,
    required BatchMode mode,
    required String engine,
    required String voice,
    required double speed,
    String outputName = 'batch',
  }) async {
    final modeStr = mode == BatchMode.reels ? 'reels' : 'long_video';
    final res = await http
        .post(
          Uri.parse('$_baseUrl/api/batch'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'mode': modeStr,
            'engine': engine,
            'voice': voice,
            'speed': speed,
            'output_name': outputName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      final err = jsonDecode(res.body)['detail'] ?? 'Error iniciando batch';
      throw Exception(err);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<BatchJobStatus> pollJob(String jobId) async {
    final res = await http
        .get(Uri.parse('$_baseUrl/api/jobs/$jobId'))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) throw Exception('Error consultando job');
    return BatchJobStatus.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<void> cancelJob(String jobId) async {
    await http
        .delete(Uri.parse('$_baseUrl/api/jobs/$jobId'))
        .timeout(const Duration(seconds: 10));
  }

  static Future<Uint8List> downloadChunk(String jobId, String filename) async {
    final url = chunkAudioUrl(jobId, filename);
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) throw Exception('Error descargando chunk');
    return res.bodyBytes;
  }
}
