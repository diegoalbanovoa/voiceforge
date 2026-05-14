import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import '../services/tts_service.dart';
import '../widgets/batch_progress_panel.dart';
import '../widgets/batch_result_list.dart';

class BatchScreen extends StatefulWidget {
  final BatchMode mode;
  final List<EngineInfo> engines;
  final EngineInfo? initialEngine;
  final VoiceOption? initialVoice;
  final double initialSpeed;

  const BatchScreen({
    super.key,
    required this.mode,
    required this.engines,
    this.initialEngine,
    this.initialVoice,
    required this.initialSpeed,
  });

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final _textController = TextEditingController();
  final _fileNameController = TextEditingController();
  final _scrollController = ScrollController();

  late EngineInfo? _selectedEngine;
  late VoiceOption? _selectedVoice;
  late double _speed;

  String? _jobId;
  BatchJobStatus? _jobStatus;
  Timer? _pollTimer;
  bool _starting = false;
  String? _error;
  String? _outputFolder;

  @override
  void initState() {
    super.initState();
    _selectedEngine = widget.initialEngine;
    _selectedVoice = widget.initialVoice;
    _speed = widget.initialSpeed;
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textController.dispose();
    _fileNameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _modeLabel =>
      widget.mode == BatchMode.reels ? 'Reels' : 'Video Largo';

  int get _chunkSize =>
      widget.mode == BatchMode.reels ? 2000 : 4000;

  int get _estimatedChunks {
    final len = _textController.text.length;
    if (len == 0) return 0;
    return (len / _chunkSize).ceil();
  }

  String get _estimatedDuration {
    final chunks = _estimatedChunks;
    if (chunks == 0) return '';
    final secsPerChunk =
        widget.mode == BatchMode.reels ? 150 : 270; // ~2:30 / ~4:30
    final totalSecs = chunks * secsPerChunk;
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    if (h > 0) return '~${h}h ${m}m de audio total';
    return '~${m}m de audio total';
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta de salida',
    );
    if (result != null) setState(() => _outputFolder = result);
  }

  Future<void> _start() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_selectedEngine == null || _selectedVoice == null) return;

    setState(() {
      _starting = true;
      _error = null;
      _jobId = null;
      _jobStatus = null;
    });

    try {
      final baseName = _fileNameController.text.trim();
      final result = await BatchService.startBatch(
        text: text,
        mode: widget.mode,
        engine: _selectedEngine!.id,
        voice: _selectedVoice!.id,
        speed: _speed,
        outputName: baseName.isNotEmpty ? baseName : 'batch',
      );

      final jobId = result['job_id'] as String;
      setState(() => _jobId = jobId);
      _startPolling(jobId);

      // Scroll to progress
      await Future.delayed(const Duration(milliseconds: 300));
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _starting = false);
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      try {
        final status = await BatchService.pollJob(jobId);
        if (mounted) {
          setState(() => _jobStatus = status);
          if (status.isDone) {
            timer.cancel();
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _cancel() async {
    if (_jobId == null) return;
    try {
      await BatchService.cancelJob(_jobId!);
    } catch (_) {}
  }

  void _onEngineChanged(EngineInfo? engine) {
    if (engine == null) return;
    setState(() {
      _selectedEngine = engine;
      _selectedVoice =
          engine.voices.isNotEmpty ? engine.voices.first : null;
      _speed = engine.speedDefault;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRunning =
        _jobId != null && (_jobStatus?.isDone == false || _jobStatus == null);
    final hasResult =
        _jobStatus != null && _jobStatus!.chunks.isNotEmpty;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Row(
          children: [
            Icon(
              widget.mode == BatchMode.reels
                  ? Icons.video_camera_back
                  : Icons.movie,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Text(_modeLabel,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.mode == BatchMode.reels ? '≤2:30/clip' : '≤5:00/clip',
                style: TextStyle(
                    fontSize: 11, color: scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTextInput(scheme),
                const SizedBox(height: 20),
                _buildSettings(scheme),
                const SizedBox(height: 16),
                _buildFolderPicker(scheme),
                const SizedBox(height: 16),
                _buildFileNameInput(scheme),
                const SizedBox(height: 20),
                _buildStartButton(scheme, isRunning),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _buildError(),
                ],
                if (_jobStatus != null) ...[
                  const SizedBox(height: 20),
                  BatchProgressPanel(
                    status: _jobStatus!,
                    onCancel: _cancel,
                  ),
                ],
                if (hasResult) ...[
                  const SizedBox(height: 20),
                  BatchResultList(
                    jobId: _jobId!,
                    chunks: _jobStatus!.chunks,
                    outputFolder: _outputFolder,
                    baseName: _fileNameController.text.trim(),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextInput(ColorScheme scheme) {
    final chars = _textController.text.length;
    final chunks = _estimatedChunks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Historia / Texto',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _textController,
          maxLines: 12,
          decoration: InputDecoration(
            hintText: 'Pega el texto completo — sin limite de caracteres...',
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
          ),
        ),
        if (chars > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 14,
                  color: scheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text(
                '$chars caracteres  •  ~$chunks audios estimados  •  $_estimatedDuration',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ],
      ],
    ).animate().fadeIn(delay: 50.ms);
  }

  Widget _buildSettings(ColorScheme scheme) {
    if (widget.engines.isEmpty) return const SizedBox();
    final isEdge = _selectedEngine?.id == 'edge';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configuracion de voz',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<EngineInfo>(
                value: _selectedEngine,
                decoration: InputDecoration(
                  labelText: 'Motor',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: widget.engines
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                e.offline ? Icons.wifi_off : Icons.cloud,
                                size: 16,
                                color:
                                    e.offline ? Colors.green : Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(e.id, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: _onEngineChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<VoiceOption>(
                value: _selectedVoice,
                decoration: InputDecoration(
                  labelText: 'Voz',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: (_selectedEngine?.voices ?? [])
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v.label,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedVoice = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.speed, size: 18),
            const SizedBox(width: 8),
            Text(
              isEdge
                  ? 'Velocidad: ${_speed > 0 ? '+' : ''}${_speed.toInt()}%'
                  : 'Velocidad: ${_speed.toStringAsFixed(1)}x',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Expanded(
              child: Slider(
                value: _speed,
                min: _selectedEngine?.speedMin ?? 0.8,
                max: _selectedEngine?.speedMax ?? 1.5,
                divisions: 20,
                onChanged: (v) => setState(() => _speed = v),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildFolderPicker(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Carpeta de salida',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_open,
                  color: scheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _outputFolder ??
                      '(Los audios se guardan en audios/batch/ del servidor)',
                  style: TextStyle(
                      fontSize: 12,
                      color: _outputFolder != null
                          ? scheme.onSurface
                          : scheme.onSurface.withValues(alpha: 0.5)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _pickFolder,
                child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 150.ms);
  }

  Widget _buildFileNameInput(ColorScheme scheme) {
    final baseName = _fileNameController.text.trim();
    final chunks = _estimatedChunks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nombre de los archivos',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _fileNameController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Ej: mi_historia  →  mi_historia_parte_1.wav',
            filled: true,
            fillColor: scheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
            prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 18),
          ),
        ),
        if (baseName.isNotEmpty && chunks > 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 14,
                  color: scheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text(
                'Se crearán: ${baseName}_parte_1  …  ${baseName}_parte_$chunks',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ],
      ],
    ).animate().fadeIn(delay: 160.ms);
  }

  Widget _buildStartButton(ColorScheme scheme, bool isRunning) {
    final chunks = _estimatedChunks;
    final canStart =
        !_starting && !isRunning && _textController.text.trim().isNotEmpty;

    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: canStart ? _start : null,
        icon: _starting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(isRunning ? Icons.hourglass_top : Icons.play_arrow),
        label: Text(
          _starting
              ? 'Iniciando...'
              : isRunning
                  ? 'Procesando...'
                  : chunks > 0
                      ? 'Generar $chunks audios'
                      : 'Generar audios',
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!,
                style:
                    const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
      ),
    ).animate().shakeX();
  }
}
