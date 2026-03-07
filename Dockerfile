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

# Publish release build
RUN dotnet publish RAG.APIs/RAG.APIs.csproj \
    -c $BUILD_CONFIGURATION \
    -o /app/publish \
    /p:UseAppHost=false \
    --no-restore

# ============================================================
# Stage 2: Runtime
# ============================================================
FROM mcr.microsoft.com/dotnet/aspnet:10.0-preview AS runtime
WORKDIR /app

# Run as non-root user for security
USER app

# Expose default HTTP port
EXPOSE 8080

# Environment variables
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

# Copy published output from build stage
COPY --from=build /app/publish .

ENTRYPOINT ["dotnet", "RAG.APIs.dll"]
