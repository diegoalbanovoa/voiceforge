"""Configura pydub para encontrar ffmpeg automaticamente."""

import logging
from pathlib import Path

logger = logging.getLogger(__name__)

_SEARCH_DIRS = [
    # Ruta estandar del sistema
    Path(r"C:\ffmpeg"),
    # Carpeta padre del proyecto (donde suele estar en este equipo)
    Path(__file__).parent.parent.parent,
    # Program Files
    Path(r"C:\Program Files\ffmpeg"),
    Path(r"C:\Program Files (x86)\ffmpeg"),
]


def configure_pydub() -> bool:
    """
    Busca ffmpeg.exe en ubicaciones conocidas y configura pydub.
    Retorna True si lo encontro, False si no.
    """
    from pydub import AudioSegment

    # 1. Verificar si ffmpeg ya esta en PATH
    import shutil
    if shutil.which("ffmpeg"):
        logger.info("ffmpeg encontrado en PATH")
        return True

    # 2. Buscar en ubicaciones conocidas
    for search_dir in _SEARCH_DIRS:
        candidates = list(search_dir.glob("**/bin/ffmpeg.exe"))
        if candidates:
            # Tomar el mas reciente si hay varios
            ffmpeg_path = str(sorted(candidates)[-1])
            AudioSegment.converter = ffmpeg_path
            AudioSegment.ffmpeg = ffmpeg_path
            logger.info(f"ffmpeg configurado: {ffmpeg_path}")
            return True

    logger.warning(
        "ffmpeg no encontrado. La exportacion a MP3 y la concatenacion de chunks "
        "no funcionaran. Descarga ffmpeg desde https://www.gyan.dev/ffmpeg/builds/"
    )
    return False
