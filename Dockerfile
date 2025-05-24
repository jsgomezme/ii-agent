# Stage 1: Build Frontend
FROM node:18-alpine as builder
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm ci
COPY frontend/ ./
# Asegúrate que el comando de build sea el correcto para el proyecto React
# Normalmente es 'npm run build', y genera una carpeta 'build' o 'dist'
RUN npm run build

# Stage 2: Python Backend
FROM python:3.10-slim

# Instalar dependencias del sistema necesarias
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ffmpeg \
    libsm6 \
    libxext6 \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Variables de entorno (se recomienda configurarlas en la plataforma de despliegue)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # Clave de Anthropic (¡CONFIGÚRALA EN LA PLATAFORMA DE DESPLIEGUE, NO AQUÍ DIRECTAMENTE!)
    ANTHROPIC_API_KEY="" \
    # Ruta donde se guardarán los workspaces de cada sesión del agente
    II_AGENT_WORKSPACE="/app/persistent_data/agent_workspaces" \
    # Ruta para los logs del servidor WebSocket
    II_AGENT_LOGS_PATH="/app/persistent_data/agent_logs/websocket_server.log" \
    # Ruta para la base de datos SQLite
    II_AGENT_DB_PATH="/app/persistent_data/database/agent.db" \
    # Modelo por defecto
    DEFAULT_MODEL="claude-3-opus-20240229" \
    # Variables para Vertex AI (si se usa)
    GCP_PROJECT_ID="" \
    GCP_REGION="" \
    # Context Manager type
    II_AGENT_CONTEXT_MANAGER="standard" \
    # URL base para archivos estáticos
    STATIC_FILE_BASE_URL="http://localhost:8000"

# Crear directorios para datos persistentes y logs ANTES de copiar el código
RUN mkdir -p /app/persistent_data/agent_workspaces \
             /app/persistent_data/agent_logs \
             /app/persistent_data/database

# Copiar y instalar dependencias de Python
COPY pyproject.toml .
RUN pip install --no-cache-dir poetry && \
    poetry config virtualenvs.create false && \
    poetry install --no-dev --no-interaction --no-ansi

# Instalar playwright y sus dependencias
RUN playwright install --with-deps chromium

# Copiar el código de la aplicación
COPY . .

# Copiar el frontend construido desde el stage anterior
# Asegúrate que la ruta /app/frontend/build sea correcta según el build de React
COPY --from=builder /app/frontend/build /app/static_frontend

# Exponer el puerto en el que corre el servidor FastAPI (ws_server.py)
EXPOSE 8000

# Comando para ejecutar la aplicación
# ws_server.py usa argumentos como --host, --port, --workspace, --logs-path
# En Docker, el host debe ser 0.0.0.0 para ser accesible desde fuera del contenedor.
# Las rutas de workspace y logs deben coincidir con los directorios creados y las ENV VARS.
CMD ["python", "ws_server.py", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workspace", "${II_AGENT_WORKSPACE}", \
     "--logs-path", "${II_AGENT_LOGS_PATH}", \
     "--context-manager", "${II_AGENT_CONTEXT_MANAGER}" \
    ] 