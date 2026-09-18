FROM node:22-slim
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm ci --omit=dev
COPY backend/ ./
COPY prompts/ /app/prompts/
COPY OuiChef/Core/Resources/catalog-tags.json /app/OuiChef/Core/Resources/catalog-tags.json
USER node
CMD ["node", "server.mjs"]
