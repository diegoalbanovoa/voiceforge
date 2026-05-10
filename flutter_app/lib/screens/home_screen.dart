import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/tts_service.dart';
import '../widgets/audio_result_card.dart';
import 'batch_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  List<EngineInfo> _engines = [];
  EngineInfo? _selectedEngine;
  VoiceOption? _selectedVoice;
  double _speed = 1.1;
  bool _loading = false;
  bool _serverOnline = false;
  GenerateResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEngines();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEngines() async {
    final online = await TTSService.checkHealth();
    setState(() => _serverOnline = online);
    if (!online) return;

    try {
      final engines = await TTSService.getEngines();
      setState(() {
        _engines = engines;
        _selectedEngine = engines.isNotEmpty ? engines.first : null;
        _selectedVoice = _selectedEngine?.voices.isNotEmpty == true
            ? _selectedEngine!.voices.first
            : null;
        _speed = _selectedEngine?.speedDefault ?? 1.1;
      });
    } catch (e) {
      setState(() => _error = 'Error cargando voces: $e');
    }
  }

  void _onEngineChanged(EngineInfo? engine) {
    if (engine == null) return;
    setState(() {
      _selectedEngine = engine;
      _selectedVoice = engine.voices.isNotEmpty ? engine.voices.first : null;
      _speed = engine.speedDefault;
      _result = null;
    });
  }

  Future<void> _generate() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_selectedEngine == null || _selectedVoice == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await TTSService.generate(
        text: text,
        engine: _selectedEngine!.id,
        voice: _selectedVoice!.id,
        speed: _speed,
      );
      setState(() => _result = result);

      // Scroll al resultado
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
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Row(
          children: [
            Icon(Icons.mic, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('TTS Studio',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  _serverOnline ? Icons.circle : Icons.circle_outlined,
                  size: 10,
                  color: _serverOnline ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  _serverOnline ? 'API online' : 'API offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: _serverOnline ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _loadEngines,
                  tooltip: 'Reconectar',
                ),
              ],
            ),
          ),
        ],
      ),
      body: !_serverOnline
          ? _buildOfflineWarning()
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildModeSelector(scheme),
                      const SizedBox(height: 24),
                      _buildTextInput(scheme),
                      const SizedBox(height: 24),
                      _buildSettings(scheme),
                      const SizedBox(height: 24),
                      _buildGenerateButton(scheme),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _buildError(),
                      ],
                      if (_result != null) ...[
                        const SizedBox(height: 24),
                        AudioResultCard(result: _result!),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildOfflineWarning() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text('API no disponible',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Inicia el servidor con uno de estos comandos:',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('# Python directo (desarrollo)',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
                Text('uvicorn api.main:app --port 8000',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
                SizedBox(height: 8),
                Text('# Docker',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
                Text('docker-compose up',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loadEngines,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  void _goToBatch(BatchMode mode) {
    if (_engines.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchScreen(
          mode: mode,
          engines: _engines,
          initialEngine: _selectedEngine,
          initialVoice: _selectedVoice,
          initialSpeed: _speed,
        ),
      ),
    );
  }

  Widget _buildModeSelector(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Modo de generacion',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.audio_file,
                title: 'Audio simple',
                subtitle: 'Un solo archivo\nhasta 10.000 chars',
                selected: true,
                onTap: null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                icon: Icons.video_camera_back,
                title: 'Reels',
                subtitle: '≤2:30 por clip\nsin limite de texto',
                selected: false,
                onTap: _engines.isNotEmpty
                    ? () => _goToBatch(BatchMode.reels)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                icon: Icons.movie,
                title: 'Video Largo',
                subtitle: '≤5:00 por clip\nsin limite de texto',
                selected: false,
                onTap: _engines.isNotEmpty
                    ? () => _goToBatch(BatchMode.longVideo)
                    : null,
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 50.ms);
  }

  Widget _buildTextInput(ColorScheme scheme) {
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
          maxLines: 10,
          decoration: InputDecoration(
            hintText: 'Escribe o pega el texto que quieres narrar...',
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
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildSettings(ColorScheme scheme) {
    if (_engines.isEmpty) return const SizedBox();

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
        // Engine + Voz en fila
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
                items: _engines
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                e.offline ? Icons.wifi_off : Icons.cloud,
                                size: 16,
                                color: e.offline ? Colors.green : Colors.blue,
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
                          child: Text(v.label, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedVoice = v;
                  _result = null;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Speed slider
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
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildGenerateButton(ColorScheme scheme) {
    final charCount = _textController.text.length;

    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: _loading || !_serverOnline ? null : _generate,
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.record_voice_over),
        label: Text(
          _loading
              ? (charCount > 5000 ? 'Generando... puede tardar varios minutos' : 'Generando audio...')
              : 'Generar audio ($charCount chars)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms);
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
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
      ),
    ).animate().shakeX();
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = onTap == null && !selected;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : disabled
                  ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? scheme.primary
                : scheme.outline.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? scheme.onPrimaryContainer
                  : disabled
                      ? scheme.onSurface.withValues(alpha: 0.3)
                      : scheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: selected
                    ? scheme.onPrimaryContainer
                    : disabled
                        ? scheme.onSurface.withValues(alpha: 0.3)
                        : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                    : scheme.onSurface.withValues(alpha: disabled ? 0.3 : 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
