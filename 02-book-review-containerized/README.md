# Project 02 — Book Review App: Containerized Full-Stack

## Overview

Containerized a production-style 3-tier web application featuring JWT-based user authentication, a RESTful API, and a MySQL relational database — all orchestrated with Docker Compose. Environment-specific configuration is injected at runtime via environment variables; no credentials are hardcoded in any image or source file.

## Architecture

```
Frontend  →  Next.js + Tailwind CSS + Axios (SSR)
                ↓  REST API calls (authenticated with JWT)
Backend   →  Node.js + Express.js + JWT + bcrypt
                ↓  Sequelize ORM
Database  →  MySQL 8
```

## Application Features

- User registration and login with JWT token authentication
- Passwords hashed with bcrypt — never stored in plain text
- Browse all books and view individual book detail pages
- Authenticated users can submit reviews with star ratings
- React Context API manages global auth state across frontend

## Project Structure

```
book-review-app/
├── frontend/
│   ├── src/
│   │   ├── app/
│   │   │   ├── page.js            # Home — book listing
│   │   │   ├── book/[id]/         # Dynamic book detail route (SSR)
│   │   │   ├── login/             # Login page
│   │   │   └── register/          # Register page
│   │   ├── components/            # Reusable UI (Navbar etc.)
│   │   ├── context/               # React Context for auth state
│   │   └── services/              # Axios API call functions
│   └── Dockerfile
├── backend/
│   ├── src/
│   │   ├── config/                # DB connection config
│   │   ├── models/                # Sequelize models: User, Book, Review
│   │   ├── routes/                # Express route handlers
│   │   ├── controllers/           # Business logic
│   │   ├── middleware/            # JWT auth middleware
│   │   └── server.js              # App entry point
│   └── Dockerfile
├── docker-compose.yml
└── .env.example                   # Template — never commit a populated .env
```

## Backend Dockerfile

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "src/server.js"]
```

## Frontend Dockerfile

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
EXPOSE 3001
CMD ["npm", "start"]
```

## docker-compose.yml

```yaml
version: "3.8"

services:
  db:
    image: mysql:8
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - mysql-data:/var/lib/mysql
    networks:
      - app-network

  backend:
    build: ./backend
    depends_on:
      - db
    environment:
      DB_HOST: db
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

## .env.example

```env
# Copy to .env and populate — NEVER commit .env to source control
DB_ROOT_PASSWORD=change-me
DB_NAME=bookreviews
DB_USER=appuser
DB_PASSWORD=change-me
JWT_SECRET=change-me-to-a-long-random-string
```

> **Security note:** All secrets are injected via environment variables at runtime.  
> The `.env` file is listed in `.gitignore` and is never committed to the repository.  
> For CI/CD, secrets are stored in the pipeline's secret variable store (e.g. Azure DevOps Library, GitHub Actions Secrets).

## Steps Performed

### 1. Create the .env file locally (not committed)

```bash
cp .env.example .env
# Edit .env with your own values
```

### 2. Build and start all services

```bash
docker-compose up --build -d
```

### 3. Verify all containers are healthy

```bash
docker ps
docker-compose logs backend
docker-compose logs frontend
```

### 4. Test end-to-end

```bash
# Access the frontend
curl http://localhost:3001

# Register a new user (use your own test values)
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"<your-email>","password":"<your-password>"}'

# Login and receive a JWT token
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"<your-email>","password":"<your-password>"}'
```

### 5. Shut down

```bash
docker-compose down        # stop and remove containers
docker-compose down -v     # also remove volumes (wipes DB data)
```

## Security Practices Applied

| Concern | Approach |
|---|---|
| Database credentials | Environment variables via `.env` (gitignored) — never hardcoded |
| JWT secret | Environment variable — never hardcoded or logged |
| Passwords at rest | bcrypt hashing — plaintext is never stored |
| Container isolation | All services on a shared internal Docker network; only frontend port is exposed externally |
| Image hygiene | `node:18-alpine` base image — minimal attack surface |

## Key Concepts Demonstrated

- Multi-service Docker Compose with `depends_on` startup ordering
- Runtime secret injection via environment variables — no credentials in images
- Named MySQL volume persisting data across container restarts
- Sequelize ORM auto-creates database tables on first boot
- JWT middleware protecting private routes (reviews, user data)
- Container-to-container communication via Docker internal DNS (service names)
- `.env.example` pattern for safe credential management in open repositories

---

**Tools:** Docker · Docker Compose · Next.js · Node.js · Express · MySQL 8 · Sequelize · JWT · bcrypt · Tailwind CSS
