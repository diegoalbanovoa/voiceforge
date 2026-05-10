# Plan de trabajo — Batch Processing (Reels & Video Largo)

> Fecha: 2026-05-10  
> Estado: pendiente de implementación  
> Estimado total: ~14 horas de desarrollo

---

## Qué se va a construir

### Modo Reels
- Divide el texto automáticamente en chunks de **máximo 2000 caracteres** (~2:00-2:30 de audio)
- Genera cada chunk como un audio independiente y numerado
- Guarda todos los archivos en la carpeta que el usuario elija
- Ejemplo: 120.000 chars → 60 audios de ~2000 chars cada uno

### Modo Video Largo
- Divide el texto en chunks de **máximo 4000 caracteres** (~4:00-5:00 de audio)
- Misma lógica que Reels pero con chunks más grandes
- Ejemplo: 1.200.000 chars → 300 audios de ~4000 chars cada uno

### Comportamiento en ambos modos
- Generación **secuencial** (un audio a la vez) para garantizar calidad
- **Barra de progreso** en tiempo real
- Indicador "Audio 12 de 60"
- **Tiempo restante estimado** (se calibra con el primer chunk)
- Lista de audios completados mientras se procesa
- Botón **Cancelar** que detiene el proceso limpiamente
- Sin límite de caracteres en el input

---

## Arquitectura de la solución

```
Flutter UI
   │  POST /api/batch  (inicia job)
   │  GET  /api/jobs/{id}  (polling cada 1.5s)
   ▼
FastAPI Backend
   │  job_id → {status, chunks, elapsed, eta}
   │  Thread separado por job (secuencial)
   ▼
TTSEngine
   │  genera chunk_01, chunk_02, ... chunk_N
   ▼
audios/batch/{job_id}/
   ├── chunk_01_reels.wav
   ├── chunk_02_reels.wav
   └── ...
```

---

## Fase 1 — Backend: Sistema de jobs batch

**Archivos a modificar/crear:** `api/main.py`, `scripts/tts_engine.py`  
**Estimado:** 4 horas

### 1.1 Modelos de datos nuevos

```python
# En api/main.py

class BatchMode(str, Enum):
    reels = "reels"        # 2000 chars/chunk → ~2:30 audio
    long_video = "long"    # 4000 chars/chunk → ~5:00 audio

class BatchRequest(BaseModel):
    text: str              # sin límite de tamaño
    mode: BatchMode
    engine: str = "kokoro"
    voice: str = "em_alex"
    speed: float = 1.1
    output_name: str = "batch"  # prefijo de los archivos

class ChunkResult(BaseModel):
    index: int
    filename: str
    chars: int
    duration_seconds: float
    status: str            # "ok" | "error"

class JobStatus(BaseModel):
    job_id: str
    mode: str
    status: str            # "pending" | "running" | "done" | "cancelled" | "error"
    total_chunks: int
    completed_chunks: int
    failed_chunks: int
    chunks: list[ChunkResult]
    elapsed_seconds: float
    eta_seconds: float | None   # None hasta completar el primer chunk
    output_dir: str        # ruta donde se guardan los archivos
```

### 1.2 Job store en memoria

```python
# Dict thread-safe con lock
import threading
_jobs: dict[str, dict] = {}
_jobs_lock = threading.Lock()
```

### 1.3 Endpoints nuevos

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/api/batch` | Crea y arranca un job de batch |
| `GET` | `/api/jobs/{job_id}` | Estado actual del job (para polling) |
| `DELETE` | `/api/jobs/{job_id}` | Cancela el job |
| `GET` | `/api/jobs/{job_id}/files` | Lista archivos generados del job |
| `GET` | `/api/jobs/{job_id}/audio/{filename}` | Descarga un audio del job |

### 1.4 Lógica de chunk_size por modo

```python
CHUNK_SIZES = {
    "reels":      2000,   # ~2:00-2:30 audio a 1.1x
    "long_video": 4000,   # ~4:00-5:00 audio a 1.1x
}
```

### 1.5 Procesamiento secuencial en thread

```python
def _run_batch_job(job_id: str, chunks: list[str], ...):
    chunk_times = []
    for i, chunk_text in enumerate(chunks):
        # Verificar cancelación antes de cada chunk
        if _jobs[job_id]["status"] == "cancelled":
            break

        t0 = time.time()
        ok = engine.generate_audio(chunk_text, output_path)
        elapsed = time.time() - t0
        chunk_times.append(elapsed)

        # Actualizar ETA con promedio de chunks completados
        avg_time = sum(chunk_times) / len(chunk_times)
        remaining = len(chunks) - (i + 1)
        eta = avg_time * remaining

        # Actualizar job en el store
        with _jobs_lock:
            _jobs[job_id]["completed_chunks"] += 1
            _jobs[job_id]["eta_seconds"] = eta
            _jobs[job_id]["chunks"].append(ChunkResult(...))
```

### 1.6 Cambios en split_text_into_chunks (tts_engine.py)

El método actual no subdivide párrafos que superan el chunk_size (BUG-07 del análisis).
Se corrige para que si un párrafo excede el límite, se divida por oraciones:

```python
def split_text_into_chunks(self, text: str, chunk_size: int = 2000) -> list[str]:
    # 1. Dividir por párrafos
    # 2. Si párrafo > chunk_size → dividir por oraciones ('. ', '! ', '? ')
    # 3. Si oración > chunk_size → cortar por palabras
```

---

## Fase 2 — Flutter: Servicios y modelos

**Archivos a modificar/crear:** `tts_service.dart`, `pubspec.yaml`  
**Estimado:** 2 horas

### 2.1 Nueva dependencia

```yaml
# pubspec.yaml
file_picker: ^8.1.2    # para selección de carpeta de salida
```

### 2.2 Nuevos modelos Dart

```dart
// En tts_service.dart

enum BatchMode { reels, longVideo }

class ChunkResult {
  final int index;
  final String filename;
  final int chars;
  final double durationSeconds;
  final String status;        // "ok" | "error"
  String get audioUrl => '$_baseUrl/api/jobs/.../audio/$filename';
}

class BatchJobStatus {
  final String jobId;
  final String status;        // "pending"|"running"|"done"|"cancelled"|"error"
  final int totalChunks;
  final int completedChunks;
  final int failedChunks;
  final List<ChunkResult> chunks;
  final double elapsedSeconds;
  final double? etaSeconds;
  
  double get progressFraction => 
      totalChunks > 0 ? completedChunks / totalChunks : 0;
  
  String get etaLabel {
    if (etaSeconds == null) return 'Calculando...';
    final mins = (etaSeconds! ~/ 60);
    final secs = (etaSeconds! % 60).toInt();
    return mins > 0 ? '~${mins}m ${secs}s restantes' : '~${secs}s restantes';
  }
}
```

### 2.3 Nuevos métodos en TTSService

```dart
// Iniciar job batch
static Future<String> startBatch({
  required String text,
  required BatchMode mode,
  required String engine,
  required String voice,
  required double speed,
  String outputName = 'batch',
}) async { ... }   // retorna job_id

// Consultar estado (para polling)
static Future<BatchJobStatus> pollJob(String jobId) async { ... }

// Cancelar
static Future<void> cancelJob(String jobId) async { ... }

// URL de audio de un chunk
static String chunkAudioUrl(String jobId, String filename) =>
    '$_baseUrl/api/jobs/$jobId/audio/$filename';
```

### 2.4 Quitar límite de caracteres

```dart
// home_screen.dart — remover maxLength: 10000
TextField(
  maxLines: 10,
  // maxLength eliminado — sin límite en modo batch
)
```

---

## Fase 3 — Flutter: UI de Batch

**Archivos a crear:** `screens/batch_screen.dart`, `widgets/batch_mode_selector.dart`,  
`widgets/batch_progress_panel.dart`, `widgets/batch_result_list.dart`  
**Archivos a modificar:** `screens/home_screen.dart`, `main.dart`  
**Estimado:** 5 horas

### 3.1 Selector de modo en HomeScreen

Reemplazar el área de configuración actual por un selector de 3 opciones:

```
┌──────────────────────────────────────────────────┐
│  Modo de generación                              │
│                                                  │
│  ┌──────────┐  ┌─────────────┐  ┌────────────┐  │
│  │   Audio  │  │   Reels     │  │   Video    │  │
│  │  simple  │  │  ≤2:30/clip │  │   Largo    │  │
│  │ (actual) │  │  sin límite │  │  ≤5:00/clip│  │
│  └──────────┘  └─────────────┘  └────────────┘  │
└──────────────────────────────────────────────────┘
```

Al elegir Reels o Video Largo → navegar a `BatchScreen`.

### 3.2 BatchScreen — Layout completo

```
┌─────────────────────────────────────────────────┐
│  ← Reels  •  TTS Studio              API ● online│
├─────────────────────────────────────────────────┤
│                                                  │
│  Historia / Texto                                │
│  ┌────────────────────────────────────────────┐  │
│  │ (área de texto sin límite de caracteres)   │  │
│  │                                            │  │
│  │                              45.320 chars  │  │
│  └────────────────────────────────────────────┘  │
│  23 audios estimados de ~2:00 c/u                │
│                                                  │
│  Configuración de voz                            │
│  [Motor ▾]  [Voz ▾]  ───●─── Velocidad 1.1x     │
│                                                  │
│  Carpeta de salida                               │
│  📁 C:\Users\diego\Videos\TikTok\  [Cambiar]    │
│                                                  │
│  [▶ Generar 23 audios]                           │
│                                                  │
├─────────────────────────────────────────────────┤
│  PROCESANDO  ████████████░░░░░░  12 / 23        │
│  Audio 12: chunk_012_reels.wav  ✓ 2:18          │
│  ~5m 30s restantes  •  Transcurrido: 4m 12s     │
│                      [■ Cancelar]                │
├─────────────────────────────────────────────────┤
│  Audios generados (12)                           │
│  ┌──────────────────────────────────────────┐    │
│  │ 01 chunk_001_reels.wav  2:12  ▶ ↓       │    │
│  │ 02 chunk_002_reels.wav  2:21  ▶ ↓       │    │
│  │ 03 chunk_003_reels.wav  2:08  ▶ ↓       │    │
│  │ ...                                      │    │
│  └──────────────────────────────────────────┘    │
│  [↓ Descargar todos]                             │
└─────────────────────────────────────────────────┘
```

### 3.3 Widget BatchProgressPanel

```dart
class BatchProgressPanel extends StatelessWidget {
  // Muestra:
  // - LinearProgressIndicator animado
  // - "Audio X de Y" con el nombre del archivo actual
  // - Duración del chunk recién completado
  // - ETA formateado
  // - Tiempo transcurrido
  // - Botón Cancelar
}
```

### 3.4 Widget BatchResultList

```dart
class BatchResultList extends StatelessWidget {
  // Lista scrolleable de chunks completados
  // Cada item:
  //   - Número de chunk
  //   - Nombre de archivo
  //   - Duración del audio
  //   - Botón reproducir (inline)
  //   - Botón descargar (individual)
  // Footer: botón "Descargar todos" → zip
}
```

### 3.5 Estimado de audios en tiempo real

Mientras el usuario escribe, mostrar debajo del texto:

```dart
// Calcular en tiempo real
final chunks = estimateChunks(text.length, mode);  
// "~23 audios estimados • ~46 min de audio total"
```

### 3.6 Polling loop

```dart
// En BatchScreen
Timer.periodic(Duration(milliseconds: 1500), (timer) async {
  final status = await TTSService.pollJob(_jobId!);
  setState(() => _jobStatus = status);
  if (status.status == 'done' || status.status == 'cancelled') {
    timer.cancel();
  }
});
```

---

## Fase 4 — Integración, pruebas y rebuild

**Estimado:** 3 horas

### 4.1 Actualizar config.yaml

```yaml
batch:
  reels_chunk_chars: 2000      # ~2:00-2:30 de audio
  long_video_chunk_chars: 4000 # ~4:00-5:00 de audio
  max_concurrent_jobs: 1       # siempre secuencial
  job_retention_hours: 24      # cuánto conservar los jobs en memoria
```

### 4.2 Actualizar README con los nuevos modos

### 4.3 Pruebas por escenario

| Escenario | Chars | Modo | Audios esperados |
|-----------|-------|------|-----------------|
| Historia corta | 800 | Reels | 1 audio |
| Guión TikTok | 8.000 | Reels | ~4 audios |
| Podcast completo | 60.000 | Reels | ~30 audios |
| Libro capítulo | 120.000 | Reels | ~60 audios |
| Video YouTube | 20.000 | Video Largo | ~5 audios |
| Cancelación | 50.000 | cualquiera | job limpiamente detenido |

### 4.4 Rebuild Flutter

```cmd
cd flutter_app
flutter build windows --release
```

### 4.5 Commit y push a GitHub

```cmd
git add -A
git commit -m "feat: batch processing - modos Reels y Video Largo con progreso en tiempo real"
git push
```

---

## Resumen de archivos nuevos/modificados

### Backend Python
| Archivo | Acción | Cambios |
|---------|--------|---------|
| `api/main.py` | Modificar | +150 líneas: endpoints batch, job store, procesamiento secuencial |
| `scripts/tts_engine.py` | Modificar | Fix split_text_into_chunks para oraciones largas |
| `scripts/config.yaml` | Modificar | Sección `batch:` nueva |

### Flutter
| Archivo | Acción | Cambios |
|---------|--------|---------|
| `pubspec.yaml` | Modificar | +file_picker |
| `lib/services/tts_service.dart` | Modificar | +modelos batch, +métodos startBatch/pollJob/cancelJob |
| `lib/screens/home_screen.dart` | Modificar | Selector de modo, sin límite chars |
| `lib/screens/batch_screen.dart` | **Crear** | Pantalla completa de batch |
| `lib/widgets/batch_mode_selector.dart` | **Crear** | Cards de selección Reels/Video Largo |
| `lib/widgets/batch_progress_panel.dart` | **Crear** | Progreso, ETA, cancelar |
| `lib/widgets/batch_result_list.dart` | **Crear** | Lista de audios generados |

---

## Orden de implementación recomendado

```
Fase 1 (backend) → Fase 2 (servicios Flutter) → Fase 3 (UI) → Fase 4 (integración)

Cada fase es independiente y se puede probar por separado:
- Fase 1: probar con curl o Postman antes de tocar Flutter
- Fase 2: unit tests de parseo JSON
- Fase 3: con datos mock antes de conectar al backend real
```
