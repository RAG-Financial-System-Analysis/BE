# RAG System

A Retrieval-Augmented Generation (RAG) system built with .NET 10 and AWS Cognito authentication.

## 🏗️ Architecture

This project follows Clean Architecture principles with the following layers:

- **RAG.APIs** - Web API layer with controllers and endpoints
- **RAG.Application** - Application services and interfaces
- **RAG.Domain** - Domain entities, DTOs, and business logic
- **RAG.Infrastructure** - Data access, external services, and AWS integrations

## 🚀 Features

- **Authentication & Authorization**
  - AWS Cognito integration for user management
  - JWT token-based authentication
  - User registration, login, and email verification
  - Role-based access control

- **Database**
  - PostgreSQL with Entity Framework Core
  - User and Role management
  - Database migrations support

## 🛠️ Technology Stack

- **.NET 10** - Latest .NET framework
- **ASP.NET Core Web API** - RESTful API development
- **Entity Framework Core** - ORM for database operations
- **PostgreSQL** - Primary database
- **AWS Cognito** - Authentication and user management
- **Swagger/OpenAPI** - API documentation

## 📋 Prerequisites

- .NET 10 SDK
- PostgreSQL database
- AWS account with Cognito User Pool configured
- Visual Studio 2022 or VS Code

## ⚙️ Configuration

1. **Database Setup**
   - Create a PostgreSQL database
   - Update connection string in `appsettings.json`

2. **AWS Cognito Setup**
   - Create a Cognito User Pool
   - Configure the following in `appsettings.json`:
   ```json
   {
     "AWS": {
       "UserPoolId": "your-user-pool-id",
       "ClientId": "your-client-id",
       "Region": "your-aws-region"
     }
   }
   ```

3. **Environment Variables**
   - Set up your AWS credentials
   - Configure database connection strings

## 🚀 Getting Started

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd RAG-System
   ```

2. **Restore dependencies**
   ```bash
   dotnet restore
   ```

3. **Update database**
   ```bash
   dotnet ef database update --project RAG.Infrastructure --startup-project RAG.APIs
   ```

4. **Run the application**
   ```bash
   dotnet run --project RAG.APIs
   ```

5. **Access the API**
   - API: `https://localhost:7xxx`
   - Swagger UI: `https://localhost:7xxx/swagger`

## 📚 API Endpoints

### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - User login
- `POST /api/auth/verify-account` - Verify email with confirmation code

## 🗄️ Database Schema

### Users Table
- `Id` (UUID) - Primary key
- `CognitoSub` (string) - AWS Cognito user identifier
- `Email` (string) - User email address
- `FullName` (string) - User's full name
- `RoleId` (UUID) - Foreign key to Roles table

### Roles Table
- `Id` (UUID) - Primary key
- `Name` (string) - Role name

## 🔧 Development

### Running Migrations
```bash
# Add new migration
dotnet ef migrations add MigrationName --project RAG.Infrastructure --startup-project RAG.APIs

# Update database
dotnet ef database update --project RAG.Infrastructure --startup-project RAG.APIs
```

### Project Structure
```
RAG-System/
├── RAG.APIs/           # Web API layer
├── RAG.Application/    # Application services
├── RAG.Domain/         # Domain entities and DTOs
├── RAG.Infrastructure/ # Data access and external services
└── Database/           # Database scripts
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📝 License

This project is licensed under the MIT License.

## 🐛 Troubleshooting

### Common Issues

1. **Database Connection Issues**
   - Verify PostgreSQL is running
   - Check connection string in `appsettings.json`

2. **AWS Cognito Issues**
   - Ensure AWS credentials are configured
   - Verify User Pool and Client ID settings
   - Check AWS region configuration

3. **Migration Issues**
   - Ensure database exists
   - Run migrations from the correct directory
   - Check Entity Framework tools are installed

## 📞 Support

For support and questions, please create an issue in the repository.