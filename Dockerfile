FROM python:3.12-slim

# Dependencias del sistema
RUN apt-get update && apt-get install -y \
    espeak-ng \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Instalar dependencias Python
COPY requirements-api.txt .
RUN pip install --no-cache-dir -r requirements-api.txt

# Copiar codigo fuente (no los modelos, se montan como volumen)
COPY scripts/ ./scripts/
COPY api/ ./api/

# Crear directorios necesarios
RUN mkdir -p audios/api_output logs models/kokoro models/piper

EXPOSE 8000

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
