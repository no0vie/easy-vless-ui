FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends bash python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/server/package.json apps/server/package.json
COPY apps/web/package.json apps/web/package.json
RUN npm ci --omit=dev --workspace=@easy-vless/server && npm cache clean --force
COPY apps/server apps/server
COPY scripts scripts
RUN mkdir -p /data/profiles && chown -R node:node /data
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3000 BASE_DIR=/data
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD node -e "fetch('http://127.0.0.1:3000/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"
CMD ["node", "apps/server/server.js"]
