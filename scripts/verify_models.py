#!/usr/bin/env python3
"""Verificar que todos los modelos estén listos"""

import os
import sys
from gtts import gTTS


def verify_gtts():
    try:
        tts = gTTS(text="Prueba", lang='es')
        tts.save("test_voice.mp3")
        os.remove("test_voice.mp3")
        print("[OK] gTTS: OK")
        return True
    except Exception as e:
        print(f"[ERROR] gTTS: ERROR - {e}")
        return False


def main():
    print("Verificando modelos...\n")

    checks = [verify_gtts()]

    if all(checks):
        print("\n[OK] Todos los modelos estan listos")
        return 0
    else:
        print("\n[ERROR] Algunos modelos requieren atencion")
        return 1


if __name__ == "__main__":
    sys.exit(main())
