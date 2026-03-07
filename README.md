# 🚀 RAG System - Backend APIs

![.NET 10](https://img.shields.io/badge/.NET-10.0-512BD4?style=for-the-badge&logo=dotnet)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![AWS Cognito](https://img.shields.io/badge/AWS_Cognito-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white)
![OpenAI](https://img.shields.io/badge/OpenAI-412991?style=for-the-badge&logo=openai&logoColor=white)

A robust Retrieval-Augmented Generation (RAG) system built with **.NET 10**, following Clean Architecture principles, utilizing Entity Framework Core with PostgreSQL, and integrated with AWS Cognito for secure authentication.

---

## 📑 Table of Contents
- [Architecture](#️-architecture)
- [Key Features](#-key-features)
- [Technology Stack](#️-technology-stack)
- [Project Structure](#-project-structure)
- [Getting Started](#-getting-started)
  - [Prerequisites](#prerequisites)
  - [Environment Variables](#environment-variables)
  - [Run with Docker (Recommended)](#run-with-docker-recommended)
  - [Run Locally](#run-locally)
- [Database Migrations](#-database-migrations)
- [API Documentation](#-api-documentation)
- [Troubleshooting](#-troubleshooting)

---

## 🏗️ Architecture

This project strictly adheres to **Clean Architecture** principles to separate concerns, ensuring testability, maintainability, and scalability.

- **`RAG.APIs`** `(Presentation Layer)`: RESTful API endpoints, Web API Controllers, and middleware configurations.
- **`RAG.Application`** `(Use Case Layer)`: Business logic, interface definitions, Services, and CQRS/MediatR handlers (if any).
- **`RAG.Domain`** `(Domain Layer)`: Core entities, Aggregates, Value Objects, exceptions, and Domain Events.
- **`RAG.Infrastructure`** `(Infrastructure Layer)`: Database Context (EF Core), external service integrations (AWS Cognito, OpenAI, S3), and Repositories.

---

## ✨ Key Features

- **🔐 Authentication & Authorization**: Integrated securely with AWS Cognito, supporting JWT token-based authentication and Role-Based Access Control (RBAC).
- **🤖 RAG Capabilities**: Integration with OpenAI to augment generation with specific context and data retrieval.
- **🗄️ Robust Data Persistence**: Built on PostgreSQL + Entity Framework Core with database migration support.
- **🐳 Containerized**: Fully Dockerized for seamless deployment (Backend + DB).

---

## 🛠️ Technology Stack

| Category | Technology |
| :--- | :--- |
| **Framework** | .NET 10 (ASP.NET Core Web API) |
| **Language** | C# 13+ |
| **Database** | PostgreSQL 16 |
| **ORM** | Entity Framework Core |
| **Authentication** | AWS Cognito |
| **AI / LLM** | OpenAI API |
| **Containerization**| Docker & Docker Compose |
| **Documentation** | Swagger / OpenAPI |

---

## 📁 Project Structure

```text
RAG-System/
├── Database/               # SQL Scripts & Database Initialization
├── RAG.APIs/               # Startup project & API Endpoints
├── RAG.Application/        # Application logic & interfaces
├── RAG.Domain/             # Core models
├── RAG.Infrastructure/     # EF Core, External APIs (AWS/OpenAI)
├── docker-compose.yml      # Multi-container local orchestration
├── Dockerfile              # Containerization instructions
└── README.md               # You are here!
```

---

## 🚀 Getting Started

### Prerequisites
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- [Docker & Docker Desktop](https://www.docker.com/products/docker-desktop/)
- Make sure ports `8080` (API) and `5432` (PostgreSQL) are free on your machine.

### Environment Variables
Create a `.env` file in the root directory by copying `.env.example`:
```bash
cp .env.example .env
```
Fill in the necessary keys (AWS credentials, OpenAI API Key, Database credentials) in the `.env` file before running the application.

### Run with Docker (Recommended)
This will spin up both the **PostgreSQL Database** and the **ASP.NET Core Backend**.

```bash
# Build and start the containers in detached mode
docker-compose up -d --build

# View logs
docker-compose logs -f backend
```
> **Note:** The database will be seeded automatically via scripts in `Database/scriptDB_final.sql`.
> Swagger will be available at: http://localhost:8080/swagger

### Run Locally
If you prefer to run it locally via Visual Studio or CLI:

1. **Setup DB:** Spin up a local PostgreSQL instance or run just the DB from docker-compose (`docker-compose up -d db`).
2. **Update Connection String:** Ensure `appsettings.Development.json` has the correct `ConnectionStrings__DefaultConnection`.
3. **Restore & Run:**
   ```bash
   dotnet restore RAG-System.slnx
   dotnet run --project RAG.APIs/RAG.APIs.csproj
   ```

---

## ⚙️ Database Migrations

During development, if you change Domain entities and need to update the database schema, run the following EF Core CLI commands:

```bash
# Generate a new migration
dotnet ef migrations add <MigrationName> --project RAG.Infrastructure --startup-project RAG.APIs

# Apply migrations to the database
dotnet ef database update --project RAG.Infrastructure --startup-project RAG.APIs
```

---

## 📚 API Documentation

Once the project is running, you can access the interactive API interface provided by **Swagger**:

- **Local Development URL**: `https://localhost:<port>/swagger` or `http://localhost:<port>/swagger`
- **Docker URL**: `http://localhost:8080/swagger`

The Swagger UI provides documentation for authentication endpoints (`/api/auth/*`) and other RAG functionality. Ensure you pass your JWT Token in the `Authorize` section if the endpoint requires authentication.

---

## 🐛 Troubleshooting

1. **Database Connection Issues (`Connection Refused`)**
   - If using `docker-compose`, ensure the `db` container is fully spun up before the `backend` container tries to connect.
   - Verify `ConnectionStrings` in `.env` matches your postgres credentials.

2. **AWS Cognito Unauthorized Errors**
   - Check if `AWS__UserPoolId` and `AWS__ClientId` are valid in your `.env` or `appsettings.json`.
   - Ensure you are passing a valid `Bearer <TOKEN>` in Swagger.

3. **OpenAI API Key Errors**
   - Ensure `OPENAI_API_KEY` is not empty and has enough quota.

---

> Maintainer: RAG System Team