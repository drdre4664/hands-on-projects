# Book Review App — Containerized Full-Stack

Containerized a production-style 3-tier web application featuring
JWT-based user authentication, a RESTful API, and a MySQL relational
database — all orchestrated with Docker Compose.

## Architecture
```
Frontend  →  Next.js + Tailwind CSS + Axios (SSR)
    ↓ REST API calls (authenticated with JWT)
Backend   →  Node.js + Express.js + JWT + bcrypt
    ↓ Sequelize ORM
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
│   │   │   ├── page.js           # Home — book listing
│   │   │   ├── book/[id]/        # Dynamic book detail route (SSR)
│   │   │   ├── login/            # Login page
│   │   │   └── register/         # Register page
│   │   ├── components/           # Reusable UI (Navbar etc.)
│   │   ├── context/              # React Context for auth state
│   │   └── services/             # Axios API call functions
│   └── Dockerfile
├── backend/
│   ├── src/
│   │   ├── config/               # DB connection config
│   │   ├── models/               # Sequelize models: User, Book, Review
│   │   ├── routes/               # Express route handlers
│   │   ├── controllers/          # Business logic
│   │   ├── middleware/           # JWT auth middleware
│   │   └── server.js             # App entry point
│   └── Dockerfile
└── docker-compose.yml
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
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: bookreviews
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
      DB_USER: root
      DB_PASSWORD: rootpassword
      DB_NAME: bookreviews
      JWT_SECRET: your_jwt_secret
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

## Steps Performed

### Build and start all services
```bash
docker-compose up --build -d
```

### Verify all containers are healthy
```bash
docker ps
docker-compose logs backend
docker-compose logs frontend
```

### Test end-to-end
```bash
# Access the app
curl http://localhost:3001

# Register a user
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"test1234"}'

# Login and get JWT token
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"test1234"}'
```

### Shut down
```bash
docker-compose down        # stop and remove containers
docker-compose down -v     # also remove volumes (wipes DB)
```

## Key Concepts Demonstrated

- Multi-service Docker Compose with `depends_on` startup ordering
- Environment variable injection for DB credentials and JWT secrets
- Named MySQL volume persisting data across container restarts
- Sequelize ORM auto-creates database tables on first boot
- JWT middleware protecting private routes (reviews, user data)
- Container-to-container communication via Docker service DNS

## Tools

`Docker` `Docker Compose` `Next.js` `Node.js` `Express` `MySQL 8` `Sequelize` `JWT` `bcrypt` `Tailwind CSS`
