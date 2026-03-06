# ============================================================
# Stage 1: Build
# ============================================================
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
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
    -c Release \
    -o /app/publish \
    --no-restore

# ============================================================
# Stage 2: Runtime
# ============================================================
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Copy published output từ stage build
COPY --from=build /app/publish .

# Expose port HTTP mặc định
EXPOSE 8080

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "RAG.APIs.dll"]
