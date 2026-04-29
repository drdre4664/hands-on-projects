# Book Review App — Containerized Full-Stack

Containerized a production-style 3-tier web application featuring JWT-based
user authentication, a RESTful API, and a relational database — all
orchestrated with Docker Compose.

## Architecture
```
Frontend  →  Next.js + Tailwind CSS + Axios
Backend   →  Node.js + Express.js + JWT + bcrypt
Database  →  MySQL + Sequelize ORM
```

## What Was Built

- Wrote Dockerfiles for both frontend and backend services independently
- Docker Compose config orchestrates all 3 tiers with correct service networking and dependency ordering
- Environment variables managed across services (API URLs, DB credentials)
- JWT authentication and bcrypt password hashing implemented in the API
- Full stack deployed to a cloud VM and verified end-to-end

## Tools

Docker · Docker Compose · Next.js · Node.js · Express · MySQL · Sequelize · JWT · Tailwind CSS
