import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/tts_service.dart';

class AudioResultCard extends StatefulWidget {
  final GenerateResult result;
  const AudioResultCard({super.key, required this.result});

  @override
  State<AudioResultCard> createState() => _AudioResultCardState();
}

class _AudioResultCardState extends State<AudioResultCard> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.stop();
      await _player.play(UrlSource(widget.result.audioUrl));
    }
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final bytes = await TTSService.downloadAudio(widget.result.audioUrl);
      final ext = widget.result.filename.endsWith('.wav') ? 'wav' : 'mp3';
      await FileSaver.instance.saveFile(
        name: 'tts_${widget.result.fileId}',
        bytes: bytes,
        ext: ext,
        mimeType: ext == 'wav' ? MimeType.custom : MimeType.mp3,
        customMimeType: ext == 'wav' ? 'audio/wav' : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio descargado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = _playerState == PlayerState.playing;

    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Audio generado',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.result.chars} chars  •  ${widget.result.durationLabel}  •  ${widget.result.engine}  •  ${widget.result.voice}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                // Play / Pause
                FilledButton.icon(
                  onPressed: _togglePlay,
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(isPlaying ? 'Pausar' : 'Reproducir'),
                ),
                const SizedBox(width: 12),
                // Descargar
                FilledButton.tonalIcon(
                  onPressed: _downloading ? null : _download,
                  icon: _downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(_downloading ? 'Descargando...' : 'Descargar'),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0);
  }
}
