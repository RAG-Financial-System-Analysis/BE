# ============================================================
# Stage 1: Build
# ============================================================
FROM mcr.microsoft.com/dotnet/sdk:10.0-preview AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

# Copy solution file & project files (tận dụng layer cache NuGet)
COPY RAG-System.slnx ./
COPY RAG.APIs/RAG.APIs.csproj            ./RAG.APIs/
COPY RAG.Application/RAG.Application.csproj ./RAG.Application/
COPY RAG.Domain/RAG.Domain.csproj        ./RAG.Domain/
COPY RAG.Infrastructure/RAG.Infrastructure.csproj ./RAG.Infrastructure/

# Restore NuGet packages
RUN dotnet restore RAG.APIs/RAG.APIs.csproj

# Copy toàn bộ source code
COPY . .

# Build and publish release build
RUN dotnet publish RAG.APIs/RAG.APIs.csproj \
    -c $BUILD_CONFIGURATION \
    -o /app/publish \
    /p:UseAppHost=false \
    --no-restore \
    --verbosity minimal

# ============================================================
# Stage 2: Runtime
# ============================================================
FROM mcr.microsoft.com/dotnet/aspnet:10.0-preview AS runtime
WORKDIR /app

# Create uploads directory with proper permissions
RUN mkdir -p /app/wwwroot/uploads/reports && \
    chmod -R 777 /app/wwwroot/uploads

# Expose HTTP port
EXPOSE 8080

# Environment variables
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV DOTNET_USE_POLLING_FILE_WATCHER=true

# Copy published output from build stage
COPY --from=build /app/publish .

# Ensure uploads directory exists and has correct permissions after copy
RUN mkdir -p /app/wwwroot/uploads/reports && \
    chmod -R 777 /app/wwwroot/uploads

ENTRYPOINT ["dotnet", "RAG.APIs.dll"]