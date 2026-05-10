#!/usr/bin/env python3
"""FastAPI backend para TTS Studio"""

import sys
import uuid
import time
import threading
import logging
from enum import Enum
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel

# Agregar scripts/ al path
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from tts_engine import TTSEngine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------- Configurar ffmpeg para pydub ----------
try:
    from ffmpeg_setup import configure_pydub
    configure_pydub()
except ImportError:
    pass

# ---------- App ----------
app = FastAPI(title="TTS Studio API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Directorios de audio
AUDIO_DIR = Path(__file__).parent.parent / "audios" / "api_output"
AUDIO_DIR.mkdir(parents=True, exist_ok=True)

BATCH_DIR = Path(__file__).parent.parent / "audios" / "batch"
BATCH_DIR.mkdir(parents=True, exist_ok=True)

# Job store en memoria (thread-safe)
_jobs: dict = {}
_jobs_lock = threading.Lock()

CHUNK_SIZES = {
    "reels":      2000,
    "long_video": 4000,
}

CONFIG_PATH = str(Path(__file__).parent.parent / "scripts" / "config.yaml")

# Cache del engine (se recrea si cambia configuracion)
_engine_cache: dict = {}

# Voces válidas por motor — para validación en /api/generate
_ENGINES_CONFIG = {
    "kokoro": {
        "label": "Kokoro (local, alta calidad)",
        "offline": True,
        "quality": "alta",
        "voices": [
            {"id": "em_alex",  "label": "Alex (masculino ES)"},
            {"id": "em_santa", "label": "Santa (masculino ES)"},
            {"id": "ef_dora",  "label": "Dora (femenino ES)"},
        ],
        "speed_min": 0.8,
        "speed_max": 1.5,
        "speed_default": 1.1,
    },
    "piper": {
        "label": "Piper TTS (local, rapido)",
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
    "edge": {
        "label": "Edge TTS (online, neural Microsoft)",
        "offline": False,
        "quality": "alta",
        "voices": [
            {"id": "es-MX-JorgeNeural",   "label": "Jorge (Mexico)"},
            {"id": "es-CO-GonzaloNeural",  "label": "Gonzalo (Colombia)"},
            {"id": "es-AR-TomasNeural",    "label": "Tomas (Argentina)"},
            {"id": "es-CL-LorenzoNeural",  "label": "Lorenzo (Chile)"},
        ],
        "speed_min": -50,
        "speed_max": 50,
        "speed_default": 15,
    },
    "google": {
        "label": "Google TTS (online)",
        "offline": False,
        "quality": "media",
        "voices": [
            {"id": "es", "label": "Espanol generico"},
        ],
        "speed_min": 0.8,
        "speed_max": 1.5,
        "speed_default": 1.0,
    },
}

_VALID_VOICES: dict[str, set] = {
    engine: {v["id"] for v in cfg["voices"]}
    for engine, cfg in _ENGINES_CONFIG.items()
}


def get_engine(engine: str, voice: str, speed) -> TTSEngine:
    key = f"{engine}:{voice}:{speed}"
    if key not in _engine_cache:
        eng = TTSEngine(config_path=CONFIG_PATH)
        eng.engine_type = engine
        eng.voice = voice
        eng.speed = speed
        _engine_cache[key] = eng
    return _engine_cache[key]


def _get_duration(path: str) -> float:
    """Devuelve la duracion del audio en segundos."""
    try:
        import soundfile as sf
        info = sf.info(path)
        return round(info.duration, 1)
    except Exception:
        try:
            from pydub import AudioSegment
            audio = AudioSegment.from_file(path)
            return round(len(audio) / 1000, 1)
        except Exception:
            return 0.0


# ---------- Modelos ----------

class GenerateRequest(BaseModel):
    text: str
    engine: str = "kokoro"
    voice: str = "em_alex"
    speed: float = 1.1


class GenerateResponse(BaseModel):
    file_id: str
    filename: str
    engine: str
    voice: str
    chars: int
    duration_seconds: float


class BatchMode(str, Enum):
    reels = "reels"
    long_video = "long_video"


class BatchRequest(BaseModel):
    text: str
    mode: BatchMode
    engine: str = "kokoro"
    voice: str = "em_alex"
    speed: float = 1.1
    output_name: str = "batch"


class ChunkResult(BaseModel):
    index: int
    filename: str
    chars: int
    duration_seconds: float
    status: str


class JobStatus(BaseModel):
    job_id: str
    mode: str
    status: str
    total_chunks: int
    completed_chunks: int
    failed_chunks: int
    chunks: list[ChunkResult]
    elapsed_seconds: float
    eta_seconds: Optional[float]
    output_dir: str


# ---------- Endpoints ----------

@app.get("/health")
def health():
    return {"status": "ok", "version": "1.0.0"}


@app.get("/api/voices")
def get_voices():
    return {"engines": _ENGINES_CONFIG}


@app.get("/api/audio")
def list_audios():
    """Lista los ultimos 20 audios generados."""
    files = sorted(
        [f for f in AUDIO_DIR.iterdir() if f.suffix in (".wav", ".mp3")],
        key=lambda f: f.stat().st_mtime,
        reverse=True,
    )
    return {
        "files": [
            {
                "filename": f.name,
                "size_kb": round(f.stat().st_size / 1024),
                "created": f.stat().st_mtime,
            }
            for f in files[:20]
        ]
    }


@app.post("/api/generate", response_model=GenerateResponse)
def generate(req: GenerateRequest, background_tasks: BackgroundTasks):
    if not req.text or not req.text.strip():
        raise HTTPException(status_code=400, detail="El texto no puede estar vacio")

    if len(req.text) > 10000:
        raise HTTPException(status_code=400, detail="Texto demasiado largo (max 10000 chars)")

    if req.engine not in _ENGINES_CONFIG:
        raise HTTPException(
            status_code=422,
            detail=f"Motor no valido: '{req.engine}'. Opciones: {list(_ENGINES_CONFIG)}"
        )

    if req.voice not in _VALID_VOICES[req.engine]:
        raise HTTPException(
            status_code=422,
            detail=f"Voz no valida para {req.engine}: '{req.voice}'"
        )

    file_id = str(uuid.uuid4())[:8]
    ext = "wav" if req.engine in ("kokoro", "piper") else "mp3"
    filename = f"tts_{req.engine}_{file_id}.{ext}"
    output_path = str(AUDIO_DIR / filename)

    try:
        engine = get_engine(req.engine, req.voice, req.speed)
        ok = engine.generate_audio(req.text.strip(), output_path)
    except Exception as e:
        logger.error(f"Error generando audio: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

    if not ok or not Path(output_path).exists():
        wav_alt = output_path.replace('.mp3', '.wav')
        if Path(wav_alt).exists():
            output_path = wav_alt
            filename = Path(wav_alt).name
        else:
            raise HTTPException(status_code=500, detail="No se genero el archivo de audio")

    duration = _get_duration(output_path)
    background_tasks.add_task(cleanup_old_files, max_files=50)

    return GenerateResponse(
        file_id=file_id,
        filename=filename,
        engine=req.engine,
        voice=req.voice,
        chars=len(req.text),
        duration_seconds=duration,
    )


@app.get("/api/audio/{filename}")
def get_audio(filename: str):
    """Reproduce o descarga el audio generado."""
    path = AUDIO_DIR / filename

    if not path.exists():
        raise HTTPException(status_code=404, detail="Archivo no encontrado")

    if not str(path.resolve()).startswith(str(AUDIO_DIR.resolve())):
        raise HTTPException(status_code=403, detail="Acceso denegado")

    media_type = "audio/wav" if filename.endswith(".wav") else "audio/mpeg"
    return FileResponse(
        path=str(path),
        media_type=media_type,
        filename=filename,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ---------- Batch processing ----------

def _run_batch_job(job_id: str, chunks: list, engine_key: str, voice: str, speed,
                   output_dir: Path, output_name: str, mode: str, ext: str):
    """Procesamiento secuencial de chunks en un thread separado."""
    chunk_times = []
    start_time = time.time()

    for i, chunk_text in enumerate(chunks):
        with _jobs_lock:
            if _jobs[job_id]["status"] == "cancelled":
                break

        filename = f"{output_name}_chunk_{i+1:03d}_{mode}.{ext}"
        output_path = str(output_dir / filename)

        t0 = time.time()
        try:
            engine = get_engine(engine_key, voice, speed)
            ok = engine.generate_audio(chunk_text, output_path)

            # Kokoro guarda como .wav aunque output sea .mp3
            if not ok or not Path(output_path).exists():
                wav_alt = output_path.replace('.mp3', '.wav')
                if Path(wav_alt).exists():
                    output_path = wav_alt
                    filename = Path(wav_alt).name
                    ok = True

            elapsed_chunk = time.time() - t0
            duration = _get_duration(output_path) if ok else 0.0

            chunk_times.append(elapsed_chunk)
            avg_time = sum(chunk_times) / len(chunk_times)
            remaining = len(chunks) - (i + 1)
            eta = avg_time * remaining

            result = ChunkResult(
                index=i + 1,
                filename=filename,
                chars=len(chunk_text),
                duration_seconds=duration,
                status="ok" if ok else "error",
            )

            with _jobs_lock:
                _jobs[job_id]["completed_chunks"] += 1
                if not ok:
                    _jobs[job_id]["failed_chunks"] += 1
                _jobs[job_id]["eta_seconds"] = eta
                _jobs[job_id]["elapsed_seconds"] = time.time() - start_time
                _jobs[job_id]["chunks"].append(result.model_dump())

        except Exception as e:
            logger.error(f"Job {job_id} chunk {i+1} error: {e}", exc_info=True)
            elapsed_chunk = time.time() - t0
            chunk_times.append(elapsed_chunk)
            result = ChunkResult(
                index=i + 1,
                filename=filename,
                chars=len(chunk_text),
                duration_seconds=0.0,
                status="error",
            )
            with _jobs_lock:
                _jobs[job_id]["completed_chunks"] += 1
                _jobs[job_id]["failed_chunks"] += 1
                _jobs[job_id]["chunks"].append(result.model_dump())

    with _jobs_lock:
        if _jobs[job_id]["status"] != "cancelled":
            _jobs[job_id]["status"] = "done"
        _jobs[job_id]["elapsed_seconds"] = time.time() - start_time
        _jobs[job_id]["eta_seconds"] = 0.0

    logger.info(f"Job {job_id} finalizado: {_jobs[job_id]['completed_chunks']}/{len(chunks)} chunks")


@app.post("/api/batch")
def start_batch(req: BatchRequest):
    if not req.text or not req.text.strip():
        raise HTTPException(status_code=400, detail="El texto no puede estar vacio")

    if req.engine not in _ENGINES_CONFIG:
        raise HTTPException(
            status_code=422,
            detail=f"Motor no valido: '{req.engine}'. Opciones: {list(_ENGINES_CONFIG)}"
        )

    if req.voice not in _VALID_VOICES[req.engine]:
        raise HTTPException(
            status_code=422,
            detail=f"Voz no valida para {req.engine}: '{req.voice}'"
        )

    chunk_size = CHUNK_SIZES[req.mode.value]
    engine_obj = get_engine(req.engine, req.voice, req.speed)
    chunks = engine_obj.split_text_into_chunks(req.text.strip(), chunk_size)

    job_id = str(uuid.uuid4())[:12]
    output_dir = BATCH_DIR / job_id
    output_dir.mkdir(parents=True, exist_ok=True)

    ext = "wav" if req.engine in ("kokoro", "piper") else "mp3"

    with _jobs_lock:
        _jobs[job_id] = {
            "job_id": job_id,
            "mode": req.mode.value,
            "status": "running",
            "total_chunks": len(chunks),
            "completed_chunks": 0,
            "failed_chunks": 0,
            "chunks": [],
            "elapsed_seconds": 0.0,
            "eta_seconds": None,
            "output_dir": str(output_dir),
        }

    t = threading.Thread(
        target=_run_batch_job,
        args=(job_id, chunks, req.engine, req.voice, req.speed,
              output_dir, req.output_name, req.mode.value, ext),
        daemon=True,
    )
    t.start()

    logger.info(f"Job {job_id} iniciado: {len(chunks)} chunks, modo={req.mode.value}")
    return {"job_id": job_id, "total_chunks": len(chunks), "output_dir": str(output_dir)}


@app.get("/api/jobs/{job_id}", response_model=JobStatus)
def get_job(job_id: str):
    with _jobs_lock:
        job = _jobs.get(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Job no encontrado")

    return JobStatus(
        job_id=job["job_id"],
        mode=job["mode"],
        status=job["status"],
        total_chunks=job["total_chunks"],
        completed_chunks=job["completed_chunks"],
        failed_chunks=job["failed_chunks"],
        chunks=[ChunkResult(**c) for c in job["chunks"]],
        elapsed_seconds=round(job["elapsed_seconds"], 1),
        eta_seconds=round(job["eta_seconds"], 1) if job["eta_seconds"] is not None else None,
        output_dir=job["output_dir"],
    )


@app.delete("/api/jobs/{job_id}")
def cancel_job(job_id: str):
    with _jobs_lock:
        if job_id not in _jobs:
            raise HTTPException(status_code=404, detail="Job no encontrado")
        if _jobs[job_id]["status"] not in ("running", "pending"):
            raise HTTPException(
                status_code=400,
                detail=f"No se puede cancelar un job en estado '{_jobs[job_id]['status']}'"
            )
        _jobs[job_id]["status"] = "cancelled"

    return {"job_id": job_id, "status": "cancelled"}


@app.get("/api/jobs/{job_id}/files")
def list_job_files(job_id: str):
    with _jobs_lock:
        job = _jobs.get(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Job no encontrado")

    output_dir = Path(job["output_dir"])
    files = sorted(output_dir.glob("*"), key=lambda f: f.name)
    return {
        "job_id": job_id,
        "files": [
            {
                "filename": f.name,
                "size_kb": round(f.stat().st_size / 1024),
            }
            for f in files if f.suffix in (".wav", ".mp3")
        ],
    }


@app.get("/api/jobs/{job_id}/audio/{filename}")
def get_job_audio(job_id: str, filename: str):
    with _jobs_lock:
        job = _jobs.get(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Job no encontrado")

    output_dir = Path(job["output_dir"])
    path = output_dir / filename

    if not path.exists():
        raise HTTPException(status_code=404, detail="Archivo no encontrado")

    if not str(path.resolve()).startswith(str(output_dir.resolve())):
        raise HTTPException(status_code=403, detail="Acceso denegado")

    media_type = "audio/wav" if filename.endswith(".wav") else "audio/mpeg"
    return FileResponse(
        path=str(path),
        media_type=media_type,
        filename=filename,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def cleanup_old_files(max_files: int = 50):
    """Elimina archivos viejos si hay mas de max_files."""
    files = sorted(AUDIO_DIR.glob("*"), key=lambda f: f.stat().st_mtime)
    for f in files[:-max_files]:
        f.unlink(missing_ok=True)
