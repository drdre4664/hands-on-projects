# Project 03 — EpicBook: Docker Compose + Nginx Reverse Proxy

## What This Project Does

This project deploys a full e-commerce bookstore application using Docker Compose, with a key focus on **network isolation** and **Nginx as a reverse proxy**. The goal is to understand how to design a container architecture where each tier can only talk to what it needs to — and nothing more.

The architecture uses two separate Docker networks. The frontend container and the backend API container share one network so the frontend can make API calls. The backend and the database share a second network. The database is on the backend-only network, which means it is completely unreachable from the frontend or the internet — even if someone tried. This is the foundation of a defence-in-depth approach to containerised applications.

## Architecture

```
Internet
    |
  port 80
    |
[Nginx — frontend container]       ← the only container exposed to the internet
    |
  frontend-network (Docker bridge)
    |
[Node.js + Express — api container] ← handles API requests
    |
  backend-network (Docker bridge)
    |
[MongoDB — db container]            ← data layer, isolated from everything else
```

### Network Isolation Design

| Network | Members | What it enables |
|---|---|---|
| `frontend-network` | ui, api | Frontend can call the API |
| `backend-network` | api, db | API can query the database |

The `db` container only exists on `backend-network`. It has no route to the internet and no route to the `ui` container. This is enforced at the Docker network level — it is not just a firewall rule that could be bypassed.

---

## docker-compose.yml

```yaml
version: "3.8"

services:

  database:
    build: ./database
    container_name: db
    restart: always           # restart automatically if the container crashes
    networks:
      - backend-network       # only on backend network — unreachable from internet
    volumes:
      - mongo-data:/data/db   # persist MongoDB data across container restarts

  backend:
    build: ./backend
    container_name: api
    restart: always
    depends_on:
      - database              # wait for db to start before launching api
    networks:
      - backend-network       # can reach the database
      - frontend-network      # can receive requests from the frontend

  frontend:
    build: ./frontend
    container_name: ui
    restart: always
    depends_on:
      - backend
    networks:
      - frontend-network      # can reach the api, but NOT the database
    ports:
      - "80:80"               # only this container is exposed to the outside world

networks:
  backend-network:
  frontend-network:

volumes:
  mongo-data:
```

---

## Dockerfiles

### Database (MongoDB)

```dockerfile
FROM mongo:latest
# MongoDB is ready to use out of the box — no extra configuration needed
EXPOSE 27017
```

### Backend (Node.js + Express)

```dockerfile
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm install express mongoose cors body-parser
COPY . .
EXPOSE 80
CMD ["node", "index.js"]
```

### Frontend (Nginx)

```dockerfile
FROM nginx:alpine
# nginx:alpine is one of the smallest production-ready images available
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## Step-by-Step Deployment

### Step 1 — Clean up any previous Docker state

**Why:** Leftover containers, images, or volumes from previous sessions can cause port conflicts or stale data issues. This wipes the local Docker environment to a clean state before starting.

```bash
docker stop $(docker ps -q)       # stop all running containers
docker rm $(docker ps -aq)        # remove all stopped containers
docker rmi -f $(docker images -q) # remove all images
docker volume prune -f             # remove unused volumes
docker network prune -f            # remove unused networks
```

### Step 2 — Build images and start the full stack

**Why:** `docker-compose up --build` reads the `docker-compose.yml` file, builds a custom Docker image for each service that has a `build:` directive, and starts all containers in the correct dependency order. The `-d` flag runs them in the background.

```bash
docker-compose up --build -d
```

### Step 3 — Verify all containers are running

**Why:** Confirm that all three services are in "Up" status before testing. If a container is in "Exit" status, check its logs immediately.

```bash
docker ps
# Expected: ui, api, db — all showing status "Up"
```

### Step 4 — Test the frontend is accessible

**Why:** Confirm that Nginx is serving the frontend on port 80.

```bash
curl http://localhost
# Or open in your browser: http://<server-public-ip>
```

### Step 5 — Verify container-to-container DNS resolution

**Why:** One of Docker Compose's most powerful features is built-in DNS. Containers can reach each other by their service name (e.g. `api`, `db`) instead of by IP address. This test confirms that DNS resolution is working across the `frontend-network`.

```bash
# Open a shell inside the frontend container
docker exec -it ui /bin/sh

# From inside the container, call the backend by its service name
curl api
# Expected response: "Hello from Backend"

exit
```

### Step 6 — Verify the backend can reach MongoDB

**Why:** This confirms that the `backend-network` is functioning and that the API container can resolve and connect to the `db` container by service name.

```bash
# Open a shell inside the api container
docker exec -it api /bin/sh

# Connect to MongoDB using its service name as the hostname
mongosh --host db --port 27017

# Run a quick test — insert a document and read it back
use testdb
db.test.insertOne({ message: "connection verified" })
db.test.find()
# Expected: document with the message field

exit
```

### Step 7 — Inspect the networks to confirm isolation

**Why:** This command shows which containers are attached to each network, confirming the isolation design is working as intended.

```bash
# Check who is on the backend network (should be: api, db)
docker network inspect backend-network

# Check who is on the frontend network (should be: ui, api — NOT db)
docker network inspect frontend-network
```

### Step 8 — Manage the running stack

```bash
# Restart a single service without touching the others
docker-compose restart backend

# Stop and remove all containers (data volume preserved)
docker-compose down

# Stop, remove containers AND delete all data volumes
docker-compose down -v
```

---

## What I Learned

- **Two-network isolation** is the correct way to segment container tiers. The database container is only on `backend-network` — it literally has no network path to the internet, regardless of any other configuration.
- **Docker Compose DNS** means containers reference each other by service name. This makes configurations portable — no IP addresses to hardcode or manage.
- **`depends_on`** controls startup order, preventing the API from trying to connect to the database before it is ready.
- **`restart: always`** makes the stack self-healing. If a container crashes, Docker automatically restarts it.
- **Named volumes** keep MongoDB data alive across container stop/start cycles. Without one, data is lost every time the container is removed.

---

**Tools Used:** Docker · Docker Compose · Nginx · Node.js · Express · MongoDB
