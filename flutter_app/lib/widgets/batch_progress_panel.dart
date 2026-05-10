import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/tts_service.dart';

class BatchProgressPanel extends StatelessWidget {
  final BatchJobStatus status;
  final VoidCallback onCancel;

  const BatchProgressPanel({
    super.key,
    required this.status,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = status.chunks.isNotEmpty ? status.chunks.last : null;
    final isDone = status.isDone;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone
              ? (status.status == 'done' ? Colors.green : Colors.orange)
              : scheme.primary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status label + cancel
          Row(
            children: [
              if (!isDone)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: scheme.primary),
                ),
              if (isDone)
                Icon(
                  status.status == 'done' ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color:
                      status.status == 'done' ? Colors.green : Colors.orange,
                ),
              const SizedBox(width: 8),
              Text(
                _statusLabel(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDone
                      ? (status.status == 'done' ? Colors.green : Colors.orange)
                      : scheme.primary,
                ),
              ),
              const Spacer(),
              if (!isDone)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop, size: 14),
                  label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: status.progressFraction,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHigh,
              color: isDone && status.status != 'done'
                  ? Colors.orange
                  : scheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          // Counters row
          Row(
            children: [
              Text(
                'Audio ${status.completedChunks} de ${status.totalChunks}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (status.failedChunks > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '(${status.failedChunks} errores)',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              const Spacer(),
              Text(
                'Transcurrido: ${status.elapsedLabel}',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
          // ETA
          if (!isDone || status.etaSeconds == 0) ...[
            const SizedBox(height: 4),
            Text(
              status.etaLabel,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
          // Current chunk info
          if (last != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.audiotrack, size: 14, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    last.filename,
                    style: const TextStyle(
                        fontSize: 12, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (last.durationSeconds > 0)
                  Text(
                    last.durationLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.7)),
                  ),
                if (last.status == 'ok')
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.check_circle,
                        size: 14, color: Colors.green),
                  ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn();
  }

  String _statusLabel() {
    switch (status.status) {
      case 'done':
        return 'Completado';
      case 'cancelled':
        return 'Cancelado';
      case 'error':
        return 'Error';
      default:
        return 'Procesando...';
    }
  }
}
