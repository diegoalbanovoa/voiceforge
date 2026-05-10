# Análisis de errores y oportunidades de mejora — TTS Studio

> Fecha del análisis: 2026-05-10  
> Versión analizada: 1.0.0  
> Archivos revisados: `api/main.py`, `scripts/tts_engine.py`, `scripts/audio_processor.py`, `scripts/main.py`, `flutter_app/lib/**`

---

## Resumen ejecutivo

| Categoría | Críticos | Medios | Menores |
|-----------|---------|--------|---------|
| Bugs Python (backend) | 3 | 3 | 4 |
| Bugs Flutter (frontend) | 0 | 0 | 3 |
| Mejoras UX | — | 5 | 4 |
| Mejoras arquitectura | — | 3 | 3 |

---

## BUGS — Errores que rompen funcionalidad

### BUG-01 · CRÍTICO · `audio_processor.py:18,42`
**`from_mp3()` usado en archivos WAV**

```python
# audio_processor.py:18  — INCORRECTO
audio = AudioSegment.from_mp3(audio_path)   # falla si el archivo es .wav

# audio_processor.py:42  — INCORRECTO
audio = AudioSegment.from_mp3(file_path)    # falla con Kokoro y Piper
```

Kokoro y Piper generan archivos `.wav`. Cuando el CLI (`scripts/main.py`) intenta concatenar múltiples chunks con `concatenate_audios()`, pydub lanza `CouldntDecodeError` al intentar decodificar WAV como MP3.

**Impacto:** Cualquier historia que supere los 2000 caracteres usando Kokoro o Piper no genera el audio final.

**Fix:**
```python
# Reemplazar from_mp3() por from_file() en ambos métodos
audio = AudioSegment.from_file(audio_path)  # detecta formato automáticamente
```

---

### BUG-02 · CRÍTICO · `scripts/main.py:59`
**Extensión del audio final siempre `.mp3` aunque el motor use WAV**

```python
# main.py:59  — INCORRECTO
final_output = os.path.join(output_dir, f"{titulo}_final.mp3")
```

Cuando el motor es `kokoro` o `piper`, los chunks individuales son `.wav`. Al intentar exportar la concatenación como `.mp3` sin ffmpeg instalado, pydub falla silenciosamente o produce un archivo inválido.

**Fix:**
```python
# Determinar extensión según el motor
ext = "wav" if self.tts_engine.engine_type in ("kokoro", "piper") else "mp3"
final_output = os.path.join(output_dir, f"{titulo}_final.{ext}")
```

---

### BUG-03 · CRÍTICO · `scripts/tts_engine.py:38-39`
**Rutas de modelos Kokoro hardcodeadas como relativas al CWD**

```python
# tts_engine.py:38-39  — FRÁGIL
self._kokoro_model = Kokoro(
    "models/kokoro/kokoro-v1.0.onnx",   # relativo al directorio de trabajo
    "models/kokoro/voices-v1.0.bin"
)
```

Si uvicorn o el CLI se ejecutan desde un directorio diferente al root del proyecto, los modelos no se encuentran y el error solo aparece al intentar generar el primer audio.

**Fix:**
```python
_BASE = Path(__file__).parent.parent  # root del proyecto

self._kokoro_model = Kokoro(
    str(_BASE / "models/kokoro/kokoro-v1.0.onnx"),
    str(_BASE / "models/kokoro/voices-v1.0.bin")
)
```

---

### BUG-04 · MEDIO · `api/main.py:182`
**`cleanup_old_files()` definida pero nunca llamada**

```python
# main.py:182 — existe pero nadie la invoca
def cleanup_old_files(max_files: int = 50):
    files = sorted(AUDIO_DIR.glob("*"), key=lambda f: f.stat().st_mtime)
    for f in files[:-max_files]:
        f.unlink(missing_ok=True)
```

El directorio `audios/api_output/` ya acumula 30+ archivos WAV (~400 MB) y seguirá creciendo indefinidamente con cada generación.

**Fix:** Invocarla como tarea en background dentro del endpoint `generate`:

```python
@app.post("/api/generate", response_model=GenerateResponse)
def generate(req: GenerateRequest, background_tasks: BackgroundTasks):
    ...
    background_tasks.add_task(cleanup_old_files, max_files=50)
    return GenerateResponse(...)
```

---

### BUG-05 · MEDIO · `api/main.py:79`
**Motor Piper excluido de la API aunque sus modelos están instalados**

```python
# get_voices() lista: kokoro, edge, google
# Piper tiene dos modelos descargados (60 MB c/u) y el código lo soporta
# pero nunca aparece en la UI porque falta en el endpoint
```

El usuario no puede usar Piper desde la interfaz gráfica.

**Fix:** Agregar a `get_voices()`:

```python
"piper": {
    "label": "Piper TTS (local, rápido)",
    "offline": True,
    "quality": "media",
    "voices": [
        {"id": "models/piper/es_MX-claude-high.onnx", "label": "Mexico alta calidad"},
        {"id": "models/piper/es_MX-ald-medium.onnx",  "label": "Mexico media calidad"},
    ],
    "speed_min": 0.8,
    "speed_max": 1.5,
    "speed_default": 1.0,
},
```

---

### BUG-06 · MEDIO · `scripts/tts_engine.py:126`
**Velocidad de Edge TTS ignorada cuando llega como número desde la API**

```python
# tts_engine.py:126  — INCORRECTO
rate = self.speed if isinstance(self.speed, str) else "+0%"
# La API manda speed=15.0 (float) → siempre usa "+0%" en vez de "+15%"
```

El slider de velocidad de la UI no tiene ningún efecto sobre Edge TTS.

**Fix:**
```python
if isinstance(self.speed, str):
    rate = self.speed
elif isinstance(self.speed, (int, float)):
    sign = "+" if self.speed >= 0 else ""
    rate = f"{sign}{int(self.speed)}%"
else:
    rate = "+0%"
```

---

### BUG-07 · MENOR · `scripts/tts_engine.py:98-119`
**`split_text_into_chunks` no divide párrafos que superan el chunk_size**

```python
# Si un párrafo individual tiene 3000 chars y chunk_size=2000,
# se añade completo como un chunk de 3000 chars — excede el límite
for para in paragraphs:
    if len(current_chunk) + len(para) <= chunk_size:
        current_chunk += para + "\n\n"
    else:
        if current_chunk:
            chunks.append(current_chunk.strip())
        current_chunk = para + "\n\n"   # ← párrafo largo sin subdividir
```

Kokoro puede fallar o generar audio incompleto con párrafos muy largos.

---

### BUG-08 · MENOR · `api/main.py:1-14`
**Imports sin usar**

```python
from typing import Optional        # no se usa en ningún tipo anotado
from fastapi import ..., BackgroundTasks  # importado pero no usado en endpoints
from fastapi.responses import ..., JSONResponse  # JSONResponse no se usa
```

Aumenta el tiempo de carga del módulo y genera confusión al leer el código.

---

### BUG-09 · MENOR · `flutter_app` — `withOpacity()` deprecado
**`audio_result_card.dart:106` y `home_screen.dart:385,388`**

```dart
// Deprecado en Flutter 3.x
color: scheme.onPrimaryContainer.withOpacity(0.7)
color: Colors.red.withOpacity(0.1)
color: Colors.red.withOpacity(0.3)
```

Genera warnings de compilación y puede comportarse diferente en futuras versiones de Flutter.

**Fix:**
```dart
color: scheme.onPrimaryContainer.withValues(alpha: 0.7)
color: Colors.red.withValues(alpha: 0.1)
```

---

### BUG-10 · MENOR · `audio_processor.py:31`
**`normalize_volume()` retorna `None` en error en vez de lanzar excepción**

```python
except Exception as e:
    logger.error(f"Error normalizando: {e}")
    return None   # el caller no puede distinguir error de resultado válido
```

Si se integra en el flujo de concatenación, un `None` causaría un `AttributeError` posterior difícil de trazar.

---

## MEJORAS — Oportunidades de mejora

### MEJORA-01 · UX · Barra de progreso para generaciones largas
**Archivo:** `flutter_app/lib/screens/home_screen.dart`

La generación de un texto de 8000 chars con Kokoro puede tardar 3-5 minutos. El usuario solo ve un spinner genérico sin ninguna indicación de progreso o tiempo estimado.

**Propuesta:** Añadir un endpoint `/api/generate/status/{job_id}` en el backend con polling desde Flutter, mostrando el porcentaje de chunks completados.

---

### MEJORA-02 · UX · Historial de audios generados en la sesión
**Archivo:** `flutter_app/lib/screens/home_screen.dart`

Cada vez que se genera un nuevo audio, el resultado anterior (`AudioResultCard`) desaparece de la UI. El usuario tiene que volver a generar si quiere comparar voces.

**Propuesta:** Mantener una lista `List<GenerateResult> _history` y mostrar los últimos 5 resultados con sus controles de reproducción.

---

### MEJORA-03 · UX · Mensaje de API offline incorrecto
**Archivo:** `flutter_app/lib/screens/home_screen.dart:193`

```dart
// El mensaje sugiere Docker cuando en Windows el flujo normal es uvicorn directo
const Text('Asegurate de que el servidor Docker esta corriendo:'),
// Y muestra:
const Text('docker-compose up', ...),
```

**Propuesta:** Mostrar las dos opciones:
```
uvicorn api.main:app --port 8000   (desarrollo)
docker-compose up                   (Docker)
```

---

### MEJORA-04 · UX · El slider de Edge TTS muestra decimals cuando debería ser entero
**Archivo:** `flutter_app/lib/screens/home_screen.dart:334`

```dart
// Edge usa rango -50 a +50 (enteros de porcentaje)
// pero el slider tiene divisions: 20 y muestra valores como "15.0%"
'Velocidad: ${_speed > 0 ? '+' : ''}${_speed.toInt()}%'
// Además, el slider no redondea correctamente entre -50 y +50 con 20 divisiones
```

**Propuesta:** Para Edge TTS, usar `divisions: 100` y forzar `_speed = _speed.roundToDouble()`.

---

### MEJORA-05 · UX · No se muestra la duración del audio generado
**Archivo:** `flutter_app/lib/widgets/audio_result_card.dart`

El `AudioResultCard` muestra caracteres, motor y voz, pero no cuánto dura el audio. El usuario no sabe si el resultado es válido hasta que lo reproduce.

**Propuesta:** Añadir `duration_seconds` a `GenerateResponse` y mostrarlo en la tarjeta.

En Python (`api/main.py`):
```python
import soundfile as sf
info = sf.info(output_path)
duration = round(info.duration, 1)
```

---

### MEJORA-06 · UX · Sin nombre personalizado al descargar
**Archivo:** `flutter_app/lib/widgets/audio_result_card.dart:50`

```dart
// El archivo siempre se descarga como "tts_0fb09363.wav"
name: 'tts_${widget.result.fileId}',
```

**Propuesta:** Añadir un campo de texto opcional "Nombre del archivo" en la UI que se pase como parámetro al endpoint de generación.

---

### MEJORA-07 · Backend · Validación de `engine` y `voice` en `/api/generate`
**Archivo:** `api/main.py:124`

```python
# Actualmente acepta cualquier string — el error 500 llega tarde (al intentar generar)
def generate(req: GenerateRequest):
    engine = get_engine(req.engine, req.voice, req.speed)  # falla si engine='invalid'
```

**Propuesta:** Validar contra los valores conocidos antes de intentar generar:

```python
VALID_ENGINES = {"kokoro", "piper", "edge", "google"}

if req.engine not in VALID_ENGINES:
    raise HTTPException(status_code=422, detail=f"Motor no válido: {req.engine}")
```

---

### MEJORA-08 · Backend · `AUDIO_DIR` como ruta absoluta
**Archivo:** `api/main.py:33`

```python
# Relativa al CWD — falla si uvicorn se arranca desde otra carpeta
AUDIO_DIR = Path("audios/api_output")
```

**Fix:**
```python
AUDIO_DIR = Path(__file__).parent.parent / "audios" / "api_output"
```

---

### MEJORA-09 · Backend · Endpoint para listar audios generados
**Archivo:** `api/main.py`

No existe ningún endpoint para que la UI consulte el historial de archivos generados anteriormente. Si el usuario cierra y reabre la app, pierde el acceso a sus audios.

**Propuesta:**
```python
@app.get("/api/audio")
def list_audios():
    files = sorted(AUDIO_DIR.glob("*.wav") | AUDIO_DIR.glob("*.mp3"),
                   key=lambda f: f.stat().st_mtime, reverse=True)
    return {"files": [{"filename": f.name, "size_kb": f.stat().st_size // 1024} for f in files[:20]]}
```

---

### MEJORA-10 · Backend · Cache de engines con límite de tamaño
**Archivo:** `api/main.py:39`

```python
# Dict global sin límite — puede crecer indefinidamente si se usan muchas combinaciones
_engine_cache: dict = {}
```

Cada engine Kokoro cargado ocupa ~350 MB en RAM. Si se crean múltiples instancias con distintas voces/speeds, el servidor puede quedarse sin memoria.

**Propuesta:** Limitar a los 3 engines más recientes con un `OrderedDict` o `functools.lru_cache`.

---

### MEJORA-11 · Arquitectura · La API no usa `split_text_into_chunks`
**Archivo:** `api/main.py:138`

```python
# La API manda el texto completo al engine en una sola llamada
ok = engine.generate_audio(req.text.strip(), output_path)
```

Pero `TTSEngine.process_historia()` ya implementa la lógica de chunking. Para textos > 2000 chars, Kokoro podría generar resultados de baja calidad o tardar demasiado sin chunking.

**Propuesta:** La API debería usar `engine.process_historia()` en lugar de `engine.generate_audio()` para textos largos, con la concatenación incluida.

---

### MEJORA-12 · Arquitectura · `verify_models.py` solo verifica gTTS
**Archivo:** `scripts/verify_models.py:24`

```python
checks = [verify_gtts()]   # solo uno de cuatro motores
```

No verifica que Kokoro o Piper puedan cargar sus modelos. El primer aviso de error llega al intentar generar audio.

**Propuesta:** Agregar verificaciones de existencia de archivos y carga de modelos para todos los motores configurados.

---

## Plan de corrección sugerido

### Fase 1 — Bugs críticos (aplicar primero, ~2 horas)

| # | Archivo | Cambio |
|---|---------|--------|
| BUG-01 | `audio_processor.py:18,42` | `from_mp3()` → `from_file()` |
| BUG-02 | `scripts/main.py:59` | extensión dinámica según engine |
| BUG-03 | `tts_engine.py:38-39` | paths absolutos con `Path(__file__)` |
| BUG-06 | `tts_engine.py:126` | convertir speed numérico a string `"+X%"` |

### Fase 2 — Bugs medios (antes del próximo release, ~3 horas)

| # | Archivo | Cambio |
|---|---------|--------|
| BUG-04 | `api/main.py` | llamar `cleanup_old_files` en BackgroundTasks |
| BUG-05 | `api/main.py:79` | agregar Piper a `get_voices()` |
| BUG-08 | `api/main.py:33` | `AUDIO_DIR` como ruta absoluta |
| BUG-10 | `audio_processor.py:31` | lanzar excepción en lugar de retornar None |

### Fase 3 — Mejoras UX prioritarias (~1 día)

| # | Área | Descripción |
|---|------|-------------|
| MEJORA-03 | Flutter | Mensaje offline con instrucciones correctas (uvicorn + Docker) |
| MEJORA-05 | Flutter + API | Mostrar duración del audio en la tarjeta de resultado |
| MEJORA-07 | API | Validar engine y voice antes de generar |
| MEJORA-09 | API | Endpoint `/api/audio` para listar historial |

### Fase 4 — Mejoras de calidad (~2 días)

| # | Área | Descripción |
|---|------|-------------|
| MEJORA-01 | Flutter + API | Progreso por chunks en textos largos |
| MEJORA-02 | Flutter | Historial de resultados en sesión |
| MEJORA-11 | API | Usar chunking en la API para textos > 2000 chars |
| MEJORA-12 | Scripts | Verificación completa de modelos |
