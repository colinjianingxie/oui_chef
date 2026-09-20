FROM node:22-slim
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv ffmpeg && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/media && /opt/media/bin/pip install --no-cache-dir yt-dlp==2026.8.19 yt-dlp-ejs==0.8.0
ENV PATH="/opt/media/bin:$PATH"
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm ci --omit=dev
COPY backend/ ./
COPY prompts/shared.md /app/prompts/shared.md
COPY OuiChef/Core/Resources/catalog-tags.json /app/OuiChef/Core/Resources/catalog-tags.json
USER node
CMD ["node", "server.mjs"]
