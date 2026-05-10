# TTS Studio — Generador de Voz para TikTok / YouTube

![Python](https://img.shields.io/badge/Python-3.12-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.41-blue)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115-green)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)
![License](https://img.shields.io/badge/License-MIT-yellow)

Aplicación de escritorio Windows + backend Python para convertir textos e historias en audio narrado, lista para publicar en TikTok y YouTube. Soporta múltiples motores de voz: modelos locales de alta calidad (sin internet) y motores online (Microsoft Edge TTS, Google TTS).

> **Los modelos de IA no están incluidos en el repositorio** por su tamaño (300+ MB).
> Ver la sección [Descarga de modelos](#descarga-de-modelos) para instalarlos.

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│               Flutter App  (Windows .exe)               │
│   UI: texto → selección de motor/voz → reproducir/bajar │
└────────────────────────┬────────────────────────────────┘
                         │  HTTP  localhost:8000
┌────────────────────────▼────────────────────────────────┐
│              FastAPI Backend  (Python 3.12)              │
│   /health  /api/voices  /api/generate  /api/audio/{f}   │
└──────┬──────────────┬────────────────┬──────────────────┘
       │              │                │
┌──────▼──────┐ ┌─────▼──────┐ ┌──────▼──────────┐
│   Kokoro    │ │   Piper    │ │  Edge / gTTS    │
│  (local)   │ │  (local)  │ │   (online)      │
│  310 MB    │ │   60 MB   │ │  sin modelos    │
└─────────────┘ └────────────┘ └─────────────────┘
```

### Estructura de directorios

```
tts-youtube-engine/
├── api/
│   └── main.py              # FastAPI — endpoints REST
├── scripts/
│   ├── config.yaml          # Configuración activa del motor
│   ├── tts_engine.py        # Lógica TTS (Kokoro/Piper/Edge/gTTS)
│   ├── audio_processor.py   # Concatenación y normalización de audio
│   ├── main.py              # CLI para procesar historias .txt
│   ├── comparar_voces.py    # Genera muestras de comparación
│   └── verify_models.py     # Verifica disponibilidad de modelos
├── flutter_app/
│   ├── lib/
│   │   ├── main.dart                    # Punto de entrada
│   │   ├── screens/home_screen.dart     # Pantalla principal
│   │   ├── services/tts_service.dart    # Cliente HTTP a la API
│   │   └── widgets/audio_result_card.dart
│   └── build/windows/x64/runner/Release/
│       └── tts_studio.exe               # Ejecutable Windows compilado
├── models/
│   ├── kokoro/
│   │   ├── kokoro-v1.0.onnx     # Modelo de síntesis (310 MB)
│   │   └── voices-v1.0.bin      # Banco de voces (27 MB)
│   └── piper/
│       ├── es_MX-claude-high.onnx       # Voz mexicana alta calidad
│       ├── es_MX-claude-high.onnx.json
│       ├── es_MX-ald-medium.onnx        # Voz mexicana media calidad
│       └── es_MX-ald-medium.onnx.json
├── audios/                  # Salida de audios generados
├── historias/               # Textos .txt de entrada
├── logs/                    # Logs de ejecución
├── Dockerfile               # Imagen Docker del backend
├── docker-compose.yml       # Orquestación Docker
├── requirements.txt         # Deps para scripts CLI
└── requirements-api.txt     # Deps para el backend FastAPI
```

---

## Modelos de voz

La aplicación **no usa Ollama**. Usa modelos ONNX locales que corren directamente en CPU/GPU, sin servidor externo y sin enviar datos a internet.

### Kokoro v1.0 (recomendado — calidad alta)

| Parámetro | Valor |
|-----------|-------|
| Formato | ONNX (runtime propio) |
| Tamaño | 310 MB (modelo) + 27 MB (voces) |
| Tipo | Neural TTS de alta calidad |
| Velocidad | Configurable (0.8 — 1.5x) |
| Conexión | 100% local, sin internet |
| Salida | WAV 24kHz |

**Voces disponibles:**

| ID | Descripción |
|----|-------------|
| `em_alex` | Masculino español — activo por defecto |
| `em_santa` | Masculino español — alternativa |
| `ef_dora` | Femenino español |

---

### Piper TTS (local, rápido)

| Parámetro | Valor |
|-----------|-------|
| Formato | ONNX |
| Tamaño | ~60 MB por modelo |
| Tipo | TTS neuronal eficiente |
| Conexión | 100% local, sin internet |
| Salida | WAV 22kHz |

**Modelos disponibles:**

| Archivo | Descripción | Calidad |
|---------|-------------|---------|
| `es_MX-claude-high.onnx` | Español México | Alta |
| `es_MX-ald-medium.onnx` | Español México | Media |

---

### Edge TTS — Microsoft (online)

| Parámetro | Valor |
|-----------|-------|
| Tipo | Neural Microsoft Azure (gratuito) |
| Conexión | Requiere internet |
| Salida | MP3 |
| Velocidad | -50% a +50% (porcentaje) |

**Voces disponibles:**

| ID | Nombre | Acento |
|----|--------|--------|
| `es-MX-JorgeNeural` | Jorge | México |
| `es-CO-GonzaloNeural` | Gonzalo | Colombia |
| `es-AR-TomasNeural` | Tomás | Argentina |
| `es-CL-LorenzoNeural` | Lorenzo | Chile |

---

### Google TTS — gTTS (online, fallback)

| Parámetro | Valor |
|-----------|-------|
| Tipo | Google Text-to-Speech |
| Conexión | Requiere internet |
| Salida | MP3 |
| Calidad | Media |

---

## Requisitos del sistema

### Software

| Requisito | Versión mínima | Notas |
|-----------|---------------|-------|
| Windows | 10 / 11 (64-bit) | Para la app de escritorio |
| Python | 3.12 | Para el backend |
| Docker Desktop | Cualquier versión actual | Opcional — alternativa a Python manual |
| ffmpeg | Cualquier versión | Solo si se quiere convertir a MP3 con Piper |

### Hardware

| Componente | Mínimo | Recomendado |
|------------|--------|-------------|
| RAM | 4 GB | 8 GB |
| CPU | 4 núcleos | 6+ núcleos |
| Disco | 600 MB libres | 2 GB (con audios generados) |
| GPU | No requerida | Acelera Kokoro si disponible |

### Dependencias Python (backend)

```
fastapi==0.115.0
uvicorn[standard]==0.30.6
pydantic==2.9.0
gtts==2.5.4
pydub==0.25.1
pyyaml==6.0.2
requests==2.32.3
edge-tts==7.2.8
kokoro-onnx==0.5.0
soundfile==0.12.1
piper-tts==1.4.2
numpy
```

---

## Descarga de modelos

Los modelos **no están en el repositorio** — deben descargarse por separado y colocarse en las carpetas indicadas.

### Kokoro v1.0 (recomendado — 337 MB total)

| Archivo | Destino | Enlace |
|---------|---------|--------|
| `kokoro-v1.0.onnx` | `models/kokoro/` | [GitHub Releases](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0) |
| `voices-v1.0.bin` | `models/kokoro/` | mismo enlace |

### Piper TTS (opcional — 60 MB c/u)

| Archivo | Destino | Enlace |
|---------|---------|--------|
| `es_MX-claude-high.onnx` + `.json` | `models/piper/` | [HuggingFace](https://huggingface.co/rhasspy/piper-voices/tree/main/es/es_MX/claude/high) |
| `es_MX-ald-medium.onnx` + `.json` | `models/piper/` | [HuggingFace](https://huggingface.co/rhasspy/piper-voices/tree/main/es/es_MX/ald/medium) |

Estructura esperada después de la descarga:

```
models/
├── kokoro/
│   ├── kokoro-v1.0.onnx   (310 MB)
│   └── voices-v1.0.bin    (27 MB)
└── piper/
    ├── es_MX-claude-high.onnx
    ├── es_MX-claude-high.onnx.json
    ├── es_MX-ald-medium.onnx
    └── es_MX-ald-medium.onnx.json
```

---

## Instalación y ejecución en Windows

Hay dos formas de ejecutar el backend: **Python directo** (más simple) o **Docker** (más estable).

### Setup automático (recomendado)

Ejecutar el script incluido — crea el entorno virtual, instala dependencias y verifica modelos:

```cmd
setup.bat
```

### Opción A — Python directo (recomendado para desarrollo)

**1. Crear y activar entorno virtual**

```cmd
python -m venv venv
venv\Scripts\activate
```

**2. Instalar dependencias del backend**

```cmd
pip install -r requirements-api.txt
```

**3. Verificar que los modelos estén presentes**

```
models\
  kokoro\
    kokoro-v1.0.onnx    (310 MB)
    voices-v1.0.bin     (27 MB)
  piper\
    es_MX-claude-high.onnx
    es_MX-claude-high.onnx.json
```

**4. Iniciar el servidor FastAPI**

```cmd
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

El servidor quedará escuchando en `http://localhost:8000`.
Verificar que funciona abriendo: `http://localhost:8000/health`

**5. Abrir la aplicación Windows**

Ejecutar el archivo `.exe` de la interfaz gráfica:

```
flutter_app\build\windows\x64\runner\Release\tts_studio.exe
```

O hacer doble clic en `tts_studio.exe` desde el explorador de archivos.

La app detecta automáticamente si el servidor está online (indicador verde en la barra superior).

---

### Opción B — Docker (recomendado para producción)

**1. Asegurarse de que Docker Desktop está corriendo**

**2. Construir e iniciar el contenedor**

```cmd
cd "C:\Users\diego\Downloads\Plan Tiktok modelo voz TTS\tts-youtube-engine"

docker-compose up --build
```

Esto construye la imagen, instala dependencias, monta los modelos como volumen y expone el puerto 8000.

**3. Abrir la aplicación Windows**

```
flutter_app\build\windows\x64\runner\Release\tts_studio.exe
```

---

## Uso de la aplicación

### Desde la interfaz gráfica (Windows)

1. Abrir `tts_studio.exe` — verificar indicador **API online** (verde) en la barra superior
2. Escribir o pegar el texto a narrar en el campo de texto (máximo 10.000 caracteres)
3. Seleccionar **Motor** y **Voz** en los desplegables
4. Ajustar la **Velocidad** con el slider
5. Hacer clic en **Generar audio**
6. Una vez generado: reproducir directamente o descargar el archivo

### Desde la línea de comandos (CLI)

Procesar un archivo `.txt` completo:

```cmd
venv\Scripts\activate
python scripts\main.py historias\ejemplo.txt mi_historia
```

Esto genera:
- `audios\mi_historia\mi_historia_final.mp3` (o `.wav` si usa Kokoro/Piper)
- `audios\mi_historia\reporte.json` con metadatos

### Cambiar el motor activo

Editar `scripts\config.yaml`:

```yaml
tts:
  engine: "kokoro"   # kokoro | piper | edge | google

voices:
  kokoro: "em_alex"                          # em_alex | em_santa | ef_dora
  piper: "models/piper/es_MX-claude-high.onnx"
  edge: "es-MX-JorgeNeural"
```

### Generar muestras de comparación de voces

```cmd
python scripts\comparar_voces.py
```

Crea archivos en `audios\comparacion_voces\` con una muestra de cada motor y voz.

### Verificar modelos disponibles

```cmd
python scripts\verify_models.py
```

---

## API REST (referencia)

El backend expone los siguientes endpoints en `http://localhost:8000`:

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/health` | Estado del servidor |
| `GET` | `/api/voices` | Lista de motores y voces disponibles |
| `POST` | `/api/generate` | Genera audio a partir de texto |
| `GET` | `/api/audio/{filename}` | Descarga o reproduce un audio generado |

**Ejemplo de petición a `/api/generate`:**

```json
POST /api/generate
{
  "text": "Había una vez un viajero en la sierra...",
  "engine": "kokoro",
  "voice": "em_alex",
  "speed": 1.1
}
```

**Respuesta:**

```json
{
  "file_id": "0fb09363",
  "filename": "tts_kokoro_0fb09363.wav",
  "engine": "kokoro",
  "voice": "em_alex",
  "chars": 44
}
```

---

## Configuración avanzada (`scripts/config.yaml`)

```yaml
tts:
  engine: "kokoro"          # Motor activo
  language: "es"
  speed: 1.1                # Kokoro/Piper: 1.0 normal | Edge: "+15%"

audio:
  format: "mp3"
  bitrate: "128k"
  sample_rate: 22050

performance:
  chunk_size: 2000           # Caracteres por fragmento (textos largos)
  parallel_processing: false
  cache_results: true
```

---

## Solución de problemas

| Problema | Causa probable | Solución |
|----------|---------------|----------|
| Indicador rojo "API offline" | El servidor no está corriendo | Ejecutar `uvicorn api.main:app --port 8000` |
| Error al generar con Kokoro | Modelos no encontrados | Verificar que `models/kokoro/*.onnx` existen |
| Error con Edge TTS | Sin conexión a internet | Cambiar a `kokoro` en `config.yaml` |
| Audio generado sin sonido | Archivo WAV corrupto (Piper) | Reinstalar `piper-tts` con `pip install piper-tts` |
| La app no abre | DLL faltante | Instalar [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe) |

---

## Notas técnicas

- Los modelos Kokoro y Piper son **ONNX** — corren en CPU sin GPU requerida.
- Esta app **no usa Ollama** ni ningún LLM. Los modelos TTS son exclusivamente de síntesis de voz.
- La primera generación con Kokoro tarda más (carga el modelo en memoria). Las siguientes son más rápidas gracias al cache de engine en la API.
- Los audios generados via API se guardan en `audios/api_output/`. Los generados via CLI en `audios/{titulo}/`.
