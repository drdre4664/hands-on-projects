# Node.js Backend — Book Review API
# Alpine base keeps the image lean (~130MB vs ~900MB for full node:18).

FROM node:18-alpine

WORKDIR /app

# Copy dependency manifest first to exploit Docker layer caching.
# npm install only re-runs if package.json changes, not on every code change.
COPY package*.json ./

# Install production dependencies only — no test frameworks or dev tools
RUN npm install --omit=dev

# Copy application source code
COPY . .

# The API listens on port 3000
EXPOSE 3000

# Exec form ensures the Node process receives Docker signals directly (graceful shutdown)
CMD ["node", "src/server.js"]
