import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_saver/file_saver.dart';
import '../services/tts_service.dart';

class BatchResultList extends StatefulWidget {
  final String jobId;
  final List<ChunkResult> chunks;

  const BatchResultList({
    super.key,
    required this.jobId,
    required this.chunks,
  });

  @override
  State<BatchResultList> createState() => _BatchResultListState();
}

class _BatchResultListState extends State<BatchResultList> {
  final _player = AudioPlayer();
  String? _playingFilename;
  final Set<String> _downloading = {};

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(ChunkResult chunk) async {
    final url = BatchService.chunkAudioUrl(widget.jobId, chunk.filename);
    if (_playingFilename == chunk.filename) {
      await _player.stop();
      setState(() => _playingFilename = null);
      return;
    }
    setState(() => _playingFilename = chunk.filename);
    await _player.play(UrlSource(url));
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingFilename = null);
    });
  }

  Future<void> _download(ChunkResult chunk) async {
    setState(() => _downloading.add(chunk.filename));
    try {
      final bytes =
          await BatchService.downloadChunk(widget.jobId, chunk.filename);
      final isWav = chunk.filename.endsWith('.wav');
      await FileSaver.instance.saveFile(
        name: chunk.filename.replaceAll(RegExp(r'\.(wav|mp3)$'), ''),
        bytes: bytes,
        ext: isWav ? 'wav' : 'mp3',
        mimeType: isWav ? MimeType.other : MimeType.mp3,
        customMimeType: isWav ? 'audio/wav' : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error descargando: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(chunk.filename));
    }
  }

  Future<void> _downloadAll() async {
    for (final chunk in widget.chunks) {
      if (chunk.status == 'ok') await _download(chunk);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final okChunks = widget.chunks.where((c) => c.status == 'ok').toList();

    if (widget.chunks.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Audios generados (${widget.chunks.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (okChunks.length > 1)
              OutlinedButton.icon(
                onPressed: _downloadAll,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Descargar todos', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.chunks.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: scheme.onSurface.withValues(alpha: 0.08),
            ),
            itemBuilder: (context, i) {
              final chunk = widget.chunks[i];
              final isPlaying = _playingFilename == chunk.filename;
              final isDownloading = _downloading.contains(chunk.filename);
              final isError = chunk.status == 'error';

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: isError
                      ? Colors.red.withValues(alpha: 0.2)
                      : scheme.primaryContainer,
                  child: Text(
                    '${chunk.index}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color:
                          isError ? Colors.red : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                title: Text(
                  chunk.filename,
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Row(
                  children: [
                    if (chunk.durationSeconds > 0)
                      Text(chunk.durationLabel,
                          style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 8),
                    Text('${chunk.chars} chars',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                scheme.onSurface.withValues(alpha: 0.5))),
                    if (isError) ...[
                      const SizedBox(width: 8),
                      const Text('ERROR',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
                trailing: isError
                    ? const Icon(Icons.error_outline,
                        color: Colors.red, size: 18)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.stop : Icons.play_arrow,
                              size: 20,
                            ),
                            onPressed: () => _play(chunk),
                            tooltip: isPlaying ? 'Detener' : 'Reproducir',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                          isDownloading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.download, size: 18),
                                  onPressed: () => _download(chunk),
                                  tooltip: 'Descargar',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}
