#!/usr/bin/env python3
"""
Script principal para generar audio de historias
Uso: python main.py <archivo_texto> [titulo]
"""

import os
import sys
import json
import logging
from pathlib import Path
from typing import Dict

# Asegurar que scripts/ esté en el path
sys.path.insert(0, os.path.dirname(__file__))

from tts_engine import TTSEngine
from audio_processor import AudioProcessor

os.makedirs("logs", exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/tts.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class HistoriaProcessor:
    """Procesa historias end-to-end"""

    def __init__(self):
        self.tts_engine = TTSEngine()
        self.audio_processor = AudioProcessor()

    def procesar_historia(self, archivo_input: str, titulo: str = None) -> Dict:
        if not os.path.exists(archivo_input):
            raise FileNotFoundError(f"Archivo no encontrado: {archivo_input}")

        with open(archivo_input, 'r', encoding='utf-8') as f:
            texto = f.read()

        logger.info(f"Historia cargada: {len(texto)} caracteres")

        if titulo is None:
            titulo = Path(archivo_input).stem

        output_dir = f"audios/{titulo}"

        logger.info("Iniciando síntesis de voz...")
        metadata = self.tts_engine.process_historia(texto, output_dir, titulo)

        if metadata['chunks_exitosos'] > 1:
            logger.info("Concatenando chunks...")
            ext = "wav" if self.tts_engine.engine_type in ("kokoro", "piper") else "mp3"
            final_output = os.path.join(output_dir, f"{titulo}_final.{ext}")

            success = self.audio_processor.concatenate_audios(
                metadata['audio_files'],
                final_output,
                silence_duration=800
            )

            if success:
                metadata['final_audio'] = final_output
                logger.info(f"✓ Audio final: {final_output}")
        elif metadata['chunks_exitosos'] == 1:
            metadata['final_audio'] = metadata['audio_files'][0]

        report = {"estado": "exitoso", "titulo": titulo, "metadata": metadata}

        report_path = os.path.join(output_dir, "reporte.json")
        with open(report_path, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)

        logger.info(f"✓ Reporte: {report_path}")
        return report


def main():
    if len(sys.argv) < 2:
        print("Uso: python scripts/main.py <archivo.txt> [titulo]")
        print("\nEjemplo:")
        print("  python scripts/main.py historias/ejemplo.txt mi_historia")
        sys.exit(1)

    archivo = sys.argv[1]
    titulo = sys.argv[2] if len(sys.argv) > 2 else None

    try:
        processor = HistoriaProcessor()
        resultado = processor.procesar_historia(archivo, titulo)

        print("\n" + "=" * 60)
        print("[OK] PROCESAMIENTO EXITOSO")
        print("=" * 60)
        print(f"Chunks generados: {resultado['metadata']['chunks_exitosos']}")
        if 'final_audio' in resultado['metadata']:
            print(f"Audio final: {resultado['metadata']['final_audio']}")

        print("=" * 60)
        return 0

    except Exception as e:
        logger.error(f"Error fatal: {e}", exc_info=True)
        print(f"\n✗ ERROR: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
