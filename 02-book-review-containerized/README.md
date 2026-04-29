# Project 02 — Book Review App: Containerized Full-Stack

## What This Project Does

This project takes a real full-stack web application — a book review platform with user authentication, a REST API, and a relational database — and containerizes it using Docker and Docker Compose. The goal is to move from "it works on my machine" to a reproducible, portable deployment where anyone can spin up the entire stack with a single command on any machine that has Docker installed.

The application has three tiers: a Next.js frontend, a Node.js/Express backend, and a MySQL 8 database. Each tier runs in its own Docker container. Containers communicate over an internal Docker network, and the only port exposed externally is the frontend port. Credentials are never hardcoded — they are injected at runtime through environment variables.

## Architecture

```
Browser
   |
port 3001 (HTTP)
   |
[Frontend — Next.js + Tailwind]      ← server-side rendered, calls backend via Axios
   |
internal Docker network (app-network)
   |
[Backend — Node.js + Express]        ← REST API, JWT auth, bcrypt password hashing
   |
internal Docker network (app-network)
   |
[Database — MySQL 8]                 ← data persisted to a named Docker volume
```

All three containers share a single internal network. The database has no port mapping to the host, so it is completely unreachable from outside Docker.

---

## How the Application Works

**Authentication flow:**
1. A user registers — the backend hashes their password with bcrypt and stores only the hash in MySQL. The plaintext password is never saved.
2. On login, the backend verifies the hash and returns a signed JWT token.
3. The frontend stores the JWT and sends it in the `Authorization` header on every subsequent API request.
4. Protected routes (posting reviews, viewing user data) are guarded by a JWT middleware — requests without a valid token are rejected.

**Data flow:**
- The frontend uses Axios to call the backend REST API for books, reviews, and auth.
- The backend uses Sequelize ORM to interact with MySQL. On first startup, Sequelize automatically creates the database tables from the model definitions — no manual SQL setup needed.

---

## Project Structure

```
book-review-app/
├── frontend/
│   ├── src/app/
│   │   ├── page.js           # Home page — lists all books
│   │   ├── book/[id]/        # Dynamic route — individual book + reviews
│   │   ├── login/            # Login page
│   │   └── register/         # Registration page
│   ├── context/              # React Context stores the JWT and user state globally
│   ├── services/             # Axios functions that call the backend API
│   └── Dockerfile
├── backend/
│   ├── src/
│   │   ├── models/           # Sequelize models — User, Book, Review
│   │   ├── routes/           # Express routes — /auth, /books, /reviews
│   │   ├── controllers/      # Business logic for each route
│   │   ├── middleware/       # JWT verification — protects private routes
│   │   └── server.js         # App entry point — starts Express server
│   └── Dockerfile
├── docker-compose.yml
└── .env.example              # Safe template — never commit a real .env file
```

---

## Dockerfiles

### Backend Dockerfile

```dockerfile
FROM node:18-alpine
# Use Alpine (minimal Linux) to keep the image small
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "src/server.js"]
```

### Frontend Dockerfile

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
# Build the Next.js app for production
RUN npm run build
EXPOSE 3001
CMD ["npm", "start"]
```

---

## docker-compose.yml

```yaml
version: "3.8"

services:

  db:
    image: mysql:8
    environment:
      # All values come from the .env file — nothing is hardcoded here
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      # Named volume ensures MySQL data survives container restarts
      - mysql-data:/var/lib/mysql
    networks:
      - app-network

  backend:
    build: ./backend
    depends_on:
      - db           # Docker Compose starts db before backend
    environment:
      DB_HOST: db    # "db" resolves to the database container via Docker DNS
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_NAME: ${DB_NAME}
      JWT_SECRET: ${JWT_SECRET}
    ports:
      - "3000:3000"
    networks:
      - app-network

  frontend:
    build: ./frontend
    depends_on:
      - backend
    environment:
      NEXT_PUBLIC_API_URL: http://backend:3000
    ports:
      - "3001:3001"
    networks:
      - app-network

networks:
  app-network:

volumes:
  mysql-data:
```

---

## .env.example

```env
# Copy this file to .env and fill in your own values
# The .env file is in .gitignore — never commit it
DB_ROOT_PASSWORD=change-me
DB_NAME=bookreviews
DB_USER=appuser
DB_PASSWORD=change-me
JWT_SECRET=replace-with-a-long-random-string
```

---

## Step-by-Step Deployment

### Step 1 — Create your local .env file

**Why:** Docker Compose reads secrets from a `.env` file in the same directory. This file is excluded from Git via `.gitignore` — credentials never touch source control.

```bash
cp .env.example .env
# Open .env and replace the placeholder values with your own
```

### Step 2 — Build images and start all containers

**Why:** The `--build` flag forces Docker to rebuild the frontend and backend images from their Dockerfiles. The `-d` flag runs everything in detached mode (background) so the terminal is free.

```bash
docker-compose up --build -d
```

### Step 3 — Verify all containers are running

**Why:** Confirm that all three services started successfully before trying to access the app. Look for "Up" status on all three containers.

```bash
docker ps

# If a container is not starting, inspect its logs to see the error
docker-compose logs backend
docker-compose logs frontend
```

### Step 4 — Access and test the application

**Why:** End-to-end testing confirms that the frontend can reach the backend, the backend can reach the database, and authentication works.

Open a browser and go to `http://localhost:3001` to use the application, or test via the API directly:

```bash
# Register a new user
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"<your-email>","password":"<your-password>"}'

# Login — the response will contain a JWT token
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"<your-email>","password":"<your-password>"}'
```

### Step 5 — Shut down

```bash
# Stop and remove containers, but keep the database volume (data preserved)
docker-compose down

# Stop and remove everything including the database volume (full wipe)
docker-compose down -v
```

---

## What I Learned

- **Multi-container Compose** with `depends_on` ensures services start in the right order. Without it, the backend might try to connect to MySQL before it is ready.
- **Docker internal DNS** means containers talk to each other by service name (e.g., `db`, `backend`) — no hardcoded IP addresses needed.
- **Named volumes** make MySQL data persist across container restarts. Without a named volume, all data is lost every time the container stops.
- **Environment variable injection** is the correct way to pass secrets to containers. Nothing sensitive is baked into an image or committed to Git.
- **bcrypt + JWT** is the standard pattern for stateless authentication: hash passwords at rest, issue signed tokens for session management.
- **Sequelize auto-sync** means the schema is managed in code — no manual database setup required.

---

**Tools Used:** Docker · Docker Compose · Next.js · Node.js · Express · MySQL 8 · Sequelize · JWT · bcrypt · Tailwind CSS
