# Project 04 — React App: Multi-Stage Docker Build & Cloud Deployment

## What This Project Does

This project demonstrates one of the most important Docker patterns for frontend applications: the **multi-stage build**. The problem it solves is this — building a React app requires Node.js, npm, and hundreds of megabytes of `node_modules`. But running the final application only requires a tiny Nginx web server serving static HTML, CSS, and JavaScript files. There is no reason to ship Node.js and all those build tools into production.

A multi-stage Dockerfile solves this by using two separate stages in a single file. Stage 1 uses a Node.js image to install dependencies and compile the React app. Stage 2 uses a minimal Nginx image and copies only the compiled output from Stage 1 — nothing else. The final image is small, clean, and contains no development tooling whatsoever.

After building the image, it is pushed to Docker Hub and then deployed to an Azure Ubuntu VM, where it is pulled and run.

## How Multi-Stage Builds Work

```
Stage 1 — "builder" (Node.js 18 Alpine)
    npm install              ← downloads all dependencies
    npm run build            ← compiles React → static files in /app/build
         |
         | COPY --from=builder /app/build   (only the output, nothing else)
         ↓
Stage 2 — "runtime" (Nginx Alpine)
    /usr/share/nginx/html    ← serves the static files
    Final image size: ~25MB  (vs ~500MB with Node.js included)
```

---

## Dockerfile

```dockerfile
# ── Stage 1: Build ──────────────────────────────────────────────────────────
FROM node:18-alpine AS builder
# Name this stage "builder" so Stage 2 can reference it

WORKDIR /app

# Copy dependency files first — Docker caches this layer if they haven't changed.
# This means subsequent builds skip npm install if only source code changed.
COPY package*.json ./
RUN npm install

# Now copy the rest of the source code and build
COPY . .
RUN npm run build
# Result: a production-optimised build is now at /app/build


# ── Stage 2: Runtime ────────────────────────────────────────────────────────
FROM nginx:alpine
# This is a fresh, minimal image — Node.js and node_modules are NOT here

# Copy only the compiled static files from the builder stage
COPY --from=builder /app/build /usr/share/nginx/html

# Nginx config: handle React Router — all routes serve index.html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
```

## nginx.conf

```nginx
server {
    listen 80;

    location / {
        root /usr/share/nginx/html;
        index index.html;

        # Critical for React Router: if a path like /about is not a real file,
        # serve index.html and let React handle the routing client-side
        try_files $uri /index.html;
    }
}
```

---

## Step-by-Step Deployment

### Step 1 — Build the Docker image locally

**Why:** The build command reads the Dockerfile, executes both stages, and produces a final image tagged with your Docker Hub username.

```bash
# Build the image — Docker runs both stages and only keeps the output of Stage 2
docker build -t <your-dockerhub-username>/react-app:latest .
```

### Step 2 — Test the image locally before pushing

**Why:** Always verify the image works on your local machine before deploying to a remote server. This catches build issues early.

```bash
docker run -p 80:80 <your-dockerhub-username>/react-app:latest
# Open browser: http://localhost — the React app should load
```

### Step 3 — Push the image to Docker Hub

**Why:** Docker Hub is a container registry — a remote store for Docker images. By pushing the image there, it becomes accessible from any machine with internet access, including the Azure VM.

```bash
# Log in to Docker Hub
docker login

# Push the image to your registry
docker push <your-dockerhub-username>/react-app:latest
```

### Step 4 — Deploy to the Azure VM

**Why:** SSH into the cloud VM, pull the image from Docker Hub, and run it. Because the image already contains everything needed to serve the app, there is no installation step on the VM — just pull and run.

```bash
# SSH into the VM
ssh <your-username>@<vm-public-ip>

# Pull the image from Docker Hub
docker pull <your-dockerhub-username>/react-app:latest

# Run the container, mapping VM port 80 to container port 80
docker run -d -p 80:80 <your-dockerhub-username>/react-app:latest
```

### Step 5 — Verify the deployment

```bash
# Confirm the container is running
docker ps

# Open in browser
# http://<vm-public-ip>  — the React app should be live
```

---

## What I Learned

- **Multi-stage builds** solve the "fat image" problem. The builder stage has all dev tooling; the runtime stage has none. Only the compiled output crosses the boundary between stages.
- **Layer caching** significantly speeds up rebuilds. Copying `package.json` and running `npm install` before copying the rest of the source means Docker reuses the cached install layer on every rebuild where dependencies haven't changed.
- **`try_files $uri /index.html`** in Nginx is essential for React Router. Without it, refreshing the page on any route other than `/` returns a 404 from Nginx because the file doesn't physically exist — React needs to handle routing on the client side.
- **Docker Hub** acts as the bridge between local development and remote deployment. Build once, run anywhere.

---

**Tools Used:** Docker Multi-Stage Build · Nginx · React · Node.js · Docker Hub · Azure VM
