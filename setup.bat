@echo off
setlocal enabledelayedexpansion
title TTS Studio - Setup

echo.
echo  ==========================================
echo   TTS Studio - Instalacion automatica
echo  ==========================================
echo.

REM Verificar Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python no encontrado. Instala Python 3.12 desde https://python.org
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('python --version') do echo [OK] %%i encontrado

REM Crear entorno virtual
echo.
echo [1/4] Creando entorno virtual...
if exist venv (
    echo       venv ya existe, omitiendo...
) else (
    python -m venv venv
    echo [OK] venv creado
)

REM Instalar dependencias
echo.
echo [2/4] Instalando dependencias Python...
venv\Scripts\pip install --quiet --upgrade pip
venv\Scripts\pip install --quiet -r requirements-api.txt
if %errorlevel% neq 0 (
    echo [ERROR] Fallo la instalacion de dependencias
    pause
    exit /b 1
)
echo [OK] Dependencias instaladas

REM Verificar modelos
echo.
echo [3/4] Verificando modelos...
echo.

if exist "models\kokoro\kokoro-v1.0.onnx" (
    echo [OK] Kokoro: kokoro-v1.0.onnx encontrado
) else (
    echo [!!] Kokoro: kokoro-v1.0.onnx NO encontrado
    echo      Descarga desde:
    echo      https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0
    echo      Archivos necesarios:  kokoro-v1.0.onnx  y  voices-v1.0.bin
    echo      Destino:              models\kokoro\
)

if exist "models\kokoro\voices-v1.0.bin" (
    echo [OK] Kokoro: voices-v1.0.bin encontrado
) else (
    echo [!!] Kokoro: voices-v1.0.bin NO encontrado
)

if exist "models\piper\es_MX-claude-high.onnx" (
    echo [OK] Piper: es_MX-claude-high.onnx encontrado
) else (
    echo [--] Piper: no encontrado ^(opcional^)
    echo      Descarga desde: https://huggingface.co/rhasspy/piper-voices
    echo      Ruta: es/es_MX/claude/high/  ->  models\piper\
)

REM Test rapido gTTS
echo.
echo [4/4] Verificando conexion y motores online...
venv\Scripts\python scripts\verify_models.py

echo.
echo  ==========================================
echo   Instalacion completada
echo  ==========================================
echo.
echo  Para iniciar el servidor:
echo.
echo    venv\Scripts\uvicorn api.main:app --host 0.0.0.0 --port 8000
echo.
echo  Luego abre la app:
echo.
echo    flutter_app\build\windows\x64\runner\Release\tts_studio.exe
echo.
pause
