#!/usr/bin/env python3
"""Genera muestras de comparacion de voces masculinas"""

import os
import asyncio
import wave
import sys

sys.path.insert(0, os.path.dirname(__file__))

TEXTO = """Habia una vez, en un pueblo alejado de la sierra colombiana, un viajero
que llegaba despues de muchos dias de camino. Sus botas estaban desgastadas,
su mochila pesaba como nunca, pero en su corazon llevaba historias de un mundo
que muy pocos llegaban a conocer."""

OUT_DIR = "audios/comparacion_voces"
os.makedirs(OUT_DIR, exist_ok=True)


async def edge_voice(voice_id: str, label: str):
    import edge_tts
    path = os.path.join(OUT_DIR, f"{label}.mp3")
    communicate = edge_tts.Communicate(text=TEXTO, voice=voice_id, rate="+15%")
    await communicate.save(path)
    size = os.path.getsize(path)
    print(f"  [OK] {label}.mp3  ({size//1024} KB)")


def piper_voice(model_path: str, label: str):
    from piper import PiperVoice
    path = os.path.join(OUT_DIR, f"{label}.wav")
    voice = PiperVoice.load(model_path)
    with wave.open(path, 'wb') as wf:
        voice.synthesize_wav(TEXTO, wf)
    size = os.path.getsize(path)
    print(f"  [OK] {label}.wav  ({size//1024} KB)")


async def main():
    print("\n=== Generando muestras Edge TTS (online, neural) ===")

    edge_voices = [
        ("es-MX-JorgeNeural",   "edge_mexico_jorge"),
        ("es-CO-GonzaloNeural", "edge_colombia_gonzalo"),
        ("es-AR-TomasNeural",   "edge_argentina_tomas"),
        ("es-CL-LorenzoNeural", "edge_chile_lorenzo"),
    ]
    for voice_id, label in edge_voices:
        try:
            await edge_voice(voice_id, label)
        except Exception as e:
            print(f"  [ERROR] {label}: {e}")

    print("\n=== Generando muestras Piper (offline, local) ===")

    piper_voices = [
        ("models/piper/es_MX-claude-high.onnx", "piper_mexico_claude_high"),
        ("models/piper/es_MX-ald-medium.onnx",  "piper_mexico_ald_medium"),
    ]
    for model_path, label in piper_voices:
        try:
            piper_voice(model_path, label)
        except Exception as e:
            print(f"  [ERROR] {label}: {e}")

    print(f"\nTodas las muestras en: {OUT_DIR}/")
    print("\nArchivos generados:")
    for f in sorted(os.listdir(OUT_DIR)):
        fpath = os.path.join(OUT_DIR, f)
        print(f"  {f}  ({os.path.getsize(fpath)//1024} KB)")


if __name__ == "__main__":
    asyncio.run(main())
