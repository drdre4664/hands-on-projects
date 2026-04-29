# ─── Stage 1: Build ───────────────────────────────────────────
FROM node:18-alpine AS build

WORKDIR /app

# Copy dependency files first (layer caching)
COPY package.json package-lock.json ./
RUN npm install

# Copy source and build
COPY . .
RUN npm run build

# ─── Stage 2: Production Runtime ──────────────────────────────
# Final image contains ONLY Nginx + static files
# No Node.js, no node_modules, no source code
FROM nginx:alpine

COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
