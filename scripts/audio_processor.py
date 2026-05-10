#!/usr/bin/env python3
"""Post-procesamiento de audio"""

import os
import logging
from typing import List
from pydub import AudioSegment
from ffmpeg_setup import configure_pydub

logger = logging.getLogger(__name__)
configure_pydub()


class AudioProcessor:
    """Procesar y mezclar audios"""

    @staticmethod
    def normalize_volume(audio_path: str, target_dbfs: float = -20.0) -> AudioSegment:
        try:
            audio = AudioSegment.from_file(audio_path)
            current_dbfs = audio.dBFS
            gain = target_dbfs - current_dbfs

            if gain != 0:
                normalized = audio.apply_gain(gain)
                logger.info(f"Audio normalizado: {current_dbfs:.2f}dB → {target_dbfs}dB")
                return normalized

            return audio

        except Exception as e:
            logger.error(f"Error normalizando: {e}")
            raise

    @staticmethod
    def concatenate_audios(audio_files: List[str],
                           output_path: str,
                           silence_duration: int = 500) -> bool:
        try:
            silence = AudioSegment.silent(duration=silence_duration)
            combined = AudioSegment.empty()

            for i, file_path in enumerate(audio_files):
                audio = AudioSegment.from_file(file_path)
                combined += audio

                if i < len(audio_files) - 1:
                    combined += silence

            combined = combined.fade_in(300).fade_out(300)
            combined.export(output_path, format="mp3", bitrate="128k")

            logger.info(f"Audios concatenados: {output_path}")
            return True

        except Exception as e:
            logger.error(f"Error concatenando: {e}")
            return False

    @staticmethod
    def convert_format(input_path: str, output_path: str, format: str = "mp3") -> bool:
        try:
            audio = AudioSegment.from_file(input_path)
            audio.export(output_path, format=format)
            logger.info(f"Convertido: {input_path} → {output_path}")
            return True

        except Exception as e:
            logger.error(f"Error convirtiendo: {e}")
            return False


def main():
    logging.basicConfig(level=logging.INFO)

    processor = AudioProcessor()

    audio_files = [
        "audios/test/historia_chunk_01.mp3",
        "audios/test/historia_chunk_02.mp3",
    ]

    processor.concatenate_audios(
        audio_files,
        "audios/test/historia_completa.mp3",
        silence_duration=800
    )


if __name__ == "__main__":
    main()
