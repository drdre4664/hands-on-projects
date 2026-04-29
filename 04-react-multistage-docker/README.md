# React App — Multi-Stage Docker Build & Cloud Deploy

Built a lean, production-ready Docker image for a React application using
a multi-stage build pattern, then deployed it to a cloud VM accessible
over a public IP.

## Build Stages
```
Stage 1 (builder)  →  Node.js: install deps, run npm run build
Stage 2 (runtime)  →  Nginx:   copy static files, serve on port 80
```

## What Was Built

- Multi-stage Dockerfile: build stage compiles the React app, runtime stage contains only Nginx + static files — no Node.js, no node_modules in the final image
- Nginx configured to handle React Router with `try_files $uri /index.html`
- Image pushed to Docker Hub and pulled on target VM for deployment
- Deployed to an Azure Ubuntu VM and verified live at `http://<public-ip>`

## Why Multi-Stage Matters

The production image is minimal — smaller attack surface, faster pulls, no dev tooling in production.

## Tools

Docker Multi-Stage Build · Nginx · React · Azure VM · Docker Hub
