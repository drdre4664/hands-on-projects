# EpicBook — Docker Compose + Nginx Reverse Proxy

Full e-commerce bookstore application deployed using a multi-service
Docker Compose stack with Nginx as a reverse proxy and strict network
isolation between application tiers.

## Architecture
```
Internet
  ↓ port 80
Nginx (reverse proxy) — frontend container
  ↓ Docker bridge (frontend-network)
Node.js + Express — backend container (api)
  ↓ Docker bridge (backend-network)
MongoDB — database container (db)
```

## Network Isolation Design

| Network | Containers | Purpose |
|---|---|---|
| `frontend-network` | ui, api | Frontend talks to backend |
| `backend-network` | api, db | Backend talks to database |

The database is NOT reachable from the internet or from the frontend —
only accessible by the backend via the internal `backend-network`.

## docker-compose.yml
```yaml
version: "3.8"

services:
  database:
    build: ./database
    container_name: db
    restart: always
    networks:
      - backend-network
    volumes:
      - mongo-data:/data/db
    ports:
      - "27017:27017"

  backend:
    build: ./backend
    container_name: api
    restart: always
    depends_on:
      - database
    networks:
      - backend-network
      - frontend-network

  frontend:
    build: ./frontend
    container_name: ui
    restart: always
    depends_on:
      - backend
    networks:
      - frontend-network
    ports:
      - "80:80"

networks:
  backend-network:
  frontend-network:

volumes:
  mongo-data:
```

## Dockerfiles

### Database (MongoDB)
```dockerfile
FROM mongo:latest
EXPOSE 27017
```

### Backend (Node.js + Express)
```dockerfile
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm init -y && npm install express mongoose cors body-parser
COPY . .
EXPOSE 80
CMD ["node", "index.js"]
```

### Frontend (Nginx)
```dockerfile
FROM nginx:alpine
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

## Steps Performed

### 1. Clean environment before starting
```bash
docker stop $(docker ps -q)
docker rm $(docker ps -aq)
docker rmi -f $(docker images -q)
docker volume prune -f
docker network prune -f
docker system prune -a -f
```

### 2. Build and start full stack
```bash
docker-compose up --build -d
```

### 3. Verify all containers running
```bash
docker ps
# Expected: ui, api, db all showing "Up"
```

### 4. Test frontend accessible
```bash
curl http://localhost
# or browser: http://<public-ip>
```

### 5. Verify container-to-container DNS resolution
```bash
# Enter frontend container
docker exec -it ui /bin/sh
apt update && apt install curl -y

# Test backend reachable by Docker service name
curl api
# Expected: Hello from Backend

exit
```

### 6. Verify backend can reach MongoDB
```bash
docker exec -it api /bin/sh
mongosh --host db --port 27017

use testdb
db.users.insertOne({ name: "Alice", age: 25 })
db.users.find()
# Expected: { _id: ..., name: "Alice", age: 25 }

exit
```

### 7. Inspect network connections
```bash
docker network inspect backend-network
docker network inspect frontend-network
```

### 8. Manage the stack
```bash
docker-compose restart backend   # restart single service
docker-compose down              # stop everything
docker-compose down -v           # stop + remove volumes
```

## Key Concepts Demonstrated

- Multi-network isolation: database hidden from internet and frontend
- `depends_on` for correct startup ordering across 3 tiers
- Docker DNS: containers reach each other by service name (e.g. `curl api`)
- Named MongoDB volume persisting data across container restarts
- `restart: always` ensures services recover automatically after failure
- One-command deployment vs 15+ manual Docker CLI commands

## Tools

`Docker` `Docker Compose` `Nginx` `Node.js` `Express` `MongoDB`
