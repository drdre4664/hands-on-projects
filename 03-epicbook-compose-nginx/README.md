# EpicBook — Docker Compose + Nginx Reverse Proxy

Deployed a full e-commerce bookstore application using a multi-service
Docker Compose stack, with Nginx acting as a reverse proxy routing
external traffic to the Node.js backend.

## App Capabilities

- Book catalogue with category filtering
- Real-time shopping cart with item count updates
- Checkout flow with order confirmation
- Nginx reverse proxy handling all inbound HTTP traffic

## What Was Built

- Dockerfile authored for the Node.js + Express backend
- Nginx configured as a reverse proxy inside its own container
- Docker Compose stack wiring together frontend, backend, database, and Nginx with a custom bridge network
- Container-to-container communication resolved via Docker DNS (service names)

## Tools

Docker · Docker Compose · Nginx · Node.js · Express · MySQL
