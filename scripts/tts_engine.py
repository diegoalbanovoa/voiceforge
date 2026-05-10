#!/usr/bin/env python3
"""Motor de sintesis de voz"""

import os
import asyncio
import json
import wave
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Dict
import yaml

_PROJECT_ROOT = Path(__file__).parent.parent

logger = logging.getLogger(__name__)

# Configurar ffmpeg para pydub (exportacion MP3, concatenacion)
try:
    from ffmpeg_setup import configure_pydub
    configure_pydub()
except ImportError:
    pass


class TTSEngine:
    """Motor de Text-to-Speech (Piper | Edge TTS | gTTS)"""

    def __init__(self, config_path: str = "scripts/config.yaml"):
        with open(config_path, 'r', encoding='utf-8') as f:
            self.config = yaml.safe_load(f)

        self.engine_type = self.config['tts']['engine']
        self.language = self.config['tts']['language']
        self.speed = self.config['tts']['speed']
        self.voice = self.config['voices'].get(self.engine_type, "es-MX-JorgeNeural")

        self._piper_voice = None   # lazy load
        self._kokoro_model = None  # lazy load

        logger.info(f"Motor TTS: {self.engine_type} | Voz: {self.voice} | Velocidad: {self.speed}")

    def _load_kokoro(self):
        if self._kokoro_model is None:
            from kokoro_onnx import Kokoro
            logger.info("Cargando modelo Kokoro...")
            self._kokoro_model = Kokoro(
                str(_PROJECT_ROOT / "models" / "kokoro" / "kokoro-v1.0.onnx"),
                str(_PROJECT_ROOT / "models" / "kokoro" / "voices-v1.0.bin")
            )
            logger.info("Kokoro listo")
        return self._kokoro_model

    def generate_audio_kokoro(self, text: str, output_path: str) -> bool:
        try:
            import soundfile as sf
            kokoro = self._load_kokoro()
            speed = self.speed if isinstance(self.speed, (int, float)) else 1.1
            samples, sr = kokoro.create(text=text, voice=self.voice, speed=speed, lang="es")
            wav_path = output_path if output_path.endswith('.wav') else output_path.replace('.mp3', '.wav')
            sf.write(wav_path, samples, sr)
            logger.info(f"Kokoro WAV guardado: {wav_path}")
            return True
        except Exception as e:
            logger.error(f"Error en Kokoro: {e}")
            return False

    def _load_piper(self):
        """Cargar modelo Piper (solo la primera vez)"""
        if self._piper_voice is None:
            from piper import PiperVoice
            logger.info(f"Cargando modelo Piper: {self.voice}")
            self._piper_voice = PiperVoice.load(self.voice)
            logger.info("Modelo Piper cargado")
        return self._piper_voice

    def generate_audio_piper(self, text: str, output_path: str) -> bool:
        """Generar audio con Piper TTS (100% local, sin internet)"""
        try:
            voice = self._load_piper()
            wav_path = output_path.replace('.mp3', '.wav')

            with wave.open(wav_path, 'wb') as wav_file:
                voice.synthesize_wav(text, wav_file)

            # output_path ya es .wav cuando engine=piper, solo mover
            if output_path.endswith('.wav'):
                os.rename(wav_path, output_path)
                logger.info(f"Piper WAV guardado: {output_path}")
            else:
                # Convertir a MP3 si ffmpeg disponible
                try:
                    from pydub import AudioSegment
                    audio = AudioSegment.from_wav(wav_path)
                    audio.export(output_path, format="mp3", bitrate="128k")
                    os.remove(wav_path)
                    logger.info(f"Piper MP3 guardado: {output_path}")
                except Exception:
                    os.rename(wav_path, output_path)
                    logger.info(f"Piper guardado como WAV: {output_path}")

            return True

        except Exception as e:
            logger.error(f"Error en Piper: {e}")
            return False

    def split_text_into_chunks(self, text: str, chunk_size: int = 2000) -> List[str]:
        text = text.strip()

        if len(text) <= chunk_size:
            return [text]

        paragraphs = text.split('\n\n')
        chunks = []
        current_chunk = ""

        for para in paragraphs:
            if len(current_chunk) + len(para) <= chunk_size:
                current_chunk += para + "\n\n"
            else:
                if current_chunk:
                    chunks.append(current_chunk.strip())
                current_chunk = para + "\n\n"

        if current_chunk:
            chunks.append(current_chunk.strip())

        return chunks

    async def _generate_edge_async(self, text: str, output_path: str) -> bool:
        """Generar audio con Edge TTS (neural, masculino, latinoamericano)"""
        try:
            import edge_tts

            if isinstance(self.speed, str):
                rate = self.speed
            elif isinstance(self.speed, (int, float)):
                sign = "+" if self.speed >= 0 else ""
                rate = f"{sign}{int(self.speed)}%"
            else:
                rate = "+0%"

            communicate = edge_tts.Communicate(
                text=text,
                voice=self.voice,
                rate=rate
            )
            await communicate.save(output_path)
            logger.info(f"Edge TTS guardado: {output_path}")
            return True

        except Exception as e:
            logger.error(f"Error en Edge TTS: {e}")
            return False

    def generate_audio_edge(self, text: str, output_path: str) -> bool:
        """Wrapper sincrono para Edge TTS"""
        return asyncio.run(self._generate_edge_async(text, output_path))

    def generate_audio_google(self, text: str, output_path: str) -> bool:
        """Generar audio con gTTS (fallback)"""
        try:
            from gtts import gTTS
            logger.info(f"Generando con gTTS: {len(text)} chars")
            tts = gTTS(text=text, lang=self.language, slow=False)
            tts.save(output_path)
            logger.info(f"gTTS guardado: {output_path}")
            return True
        except Exception as e:
            logger.error(f"Error en gTTS: {e}")
            return False

    def generate_audio(self, text: str, output_path: str) -> bool:
        """Generar audio con el motor configurado"""
        if self.engine_type == "kokoro":
            return self.generate_audio_kokoro(text, output_path)
        elif self.engine_type == "piper":
            return self.generate_audio_piper(text, output_path)
        elif self.engine_type == "edge":
            return self.generate_audio_edge(text, output_path)
        else:
            return self.generate_audio_google(text, output_path)

    def process_historia(self, text: str, output_dir: str, titulo: str = "historia") -> Dict:
        os.makedirs(output_dir, exist_ok=True)

        chunks = self.split_text_into_chunks(text, self.config['performance']['chunk_size'])
        logger.info(f"Historia dividida en {len(chunks)} chunks")

        ext = "wav" if self.engine_type in ("piper", "kokoro") else "mp3"
        audio_files = []
        for i, chunk in enumerate(chunks, 1):
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            audio_file = os.path.join(output_dir, f"{titulo}_chunk_{i:02d}_{timestamp}.{ext}")

            if self.generate_audio(chunk, audio_file):
                audio_files.append(audio_file)
                logger.info(f"Chunk {i}/{len(chunks)}: OK")
            else:
                logger.warning(f"Chunk {i}/{len(chunks)}: FALLO")

        metadata = {
            "titulo": titulo,
            "fecha": datetime.now().isoformat(),
            "chunks_totales": len(chunks),
            "chunks_exitosos": len(audio_files),
            "audio_files": audio_files,
            "total_caracteres": len(text),
            "config": {
                "engine": self.engine_type,
                "voice": self.voice,
                "speed": self.speed
            }
        }

        metadata_file = os.path.join(output_dir, "metadata.json")
        with open(metadata_file, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        logger.info(f"Metadata guardada: {metadata_file}")
        return metadata


def main():
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    engine = TTSEngine()

    texto_ejemplo = """
    Habia una vez, en un pueblo alejado de la sierra colombiana, un viajero
    que llegaba despues de muchos dias de camino. Sus botas estaban desgastadas,
    su mochila pesaba como nunca, pero en su corazon llevaba historias de un mundo
    que muy pocos llegaban a conocer.
    """

    metadata = engine.process_historia(
        texto_ejemplo,
        output_dir="audios/test",
        titulo="viajero_sierra"
    )

    print("\n[OK] Procesamiento completado")
    print(f"Archivos generados: {metadata['chunks_exitosos']}")


if __name__ == "__main__":
    main()
