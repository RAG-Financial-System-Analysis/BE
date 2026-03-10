# 🐳 Hướng dẫn chạy RAG System bằng Docker

> Dành cho FE team — **không cần cài Visual Studio hay .NET SDK**, chỉ cần Docker.

---

## ✅ Yêu cầu

| Công cụ        | Phiên bản tối thiểu | Link tải                                                      |
| -------------- | ------------------- | ------------------------------------------------------------- |
| Docker Desktop | 4.x                 | [docker.com/get-started](https://www.docker.com/get-started/) |
| Git            | bất kỳ              | [git-scm.com](https://git-scm.com/)                           |

---

## 🚀 Các bước chạy

### 1. Clone repo

```bash
git clone <repo-url>
cd RAG-System
```

### 2. Tạo file `.env`

```bash
# Windows (Command Prompt)
copy .env.example .env

# Windows (PowerShell)
Copy-Item .env.example .env

# macOS / Linux
cp .env.example .env
```

Mở file `.env` và điền các giá trị thật:

```env
# Bắt buộc phải sửa
DB_PASSWORD=your_strong_password

# AWS Configuration
AWS_USER_POOL_ID=ap-southeast-1_XXXXXXXX
AWS_CLIENT_ID=your_cognito_client_id
AWS_ACCESS_KEY=your_aws_access_key
AWS_SECRET_KEY=your_aws_secret_key
AWS_AUTHORITY=https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_XXXXXXXX
AWS_S3_BUCKET=your-s3-bucket-name

# Gemini AI (Primary - hiện tại đang dùng)
GEMINI_API_KEY=your_gemini_api_key

# OpenAI (Backup - đã comment out)
# OPENAI_API_KEY=sk-your_openai_api_key
```

> 💬 Liên hệ **BE team** để lấy các giá trị AWS và **Gemini API key**.

### 3. Build và khởi động

```bash
docker compose up --build -d
```

> Lần đầu build sẽ mất khoảng **3-7 phút** (tải .NET 10 Preview SDK + NuGet packages). Các lần sau sẽ nhanh hơn nhờ layer cache.

### 4. Kiểm tra đã chạy chưa

```bash
docker compose ps
```

Kết quả mong đợi:

```
NAME           STATUS          PORTS
rag_db         running (healthy)   0.0.0.0:5432->5432/tcp
rag_backend    running             0.0.0.0:8080->8080/tcp
```

---

## 🌐 Truy cập API

| Endpoint         | URL                           |
| ---------------- | ----------------------------- |
| **Swagger UI**   | http://localhost:8080/swagger |
| **API Base URL** | http://localhost:8080         |

Cấu hình base URL trong frontend:

```
VITE_API_URL=http://localhost:8080
# hoặc
REACT_APP_API_URL=http://localhost:8080
```

---

## 📱 Khi BE team gửi file appsettings

### Vấn đề
Khi FE team clone code BE về, sẽ **không có** 2 files:
- `appsettings.json`
- `appsettings.Development.json`

BE team sẽ gửi riêng 2 files này qua email/chat.

### 📁 **Đặt 2 files ở đâu:**

```
RAG.APIs/
├── Controllers/
├── Properties/
├── appsettings.json              ← Đặt file này ở đây
├── appsettings.Development.json  ← Đặt file này ở đây
├── Program.cs
└── RAG.APIs.csproj
```

**Đường dẫn đầy đủ:**
- `D:\FPT\semester-7\SWD\code\TestDeployLambda\BE\RAG.APIs\appsettings.json`
- `D:\FPT\semester-7\SWD\code\TestDeployLambda\BE\RAG.APIs\appsettings.Development.json`

### ✅ **Sau khi đặt xong:**

1. **Kiểm tra files đã có:**
```bash
ls RAG.APIs/appsettings*.json
```

2. **Chạy Docker như bình thường:**
```bash
docker compose up --build -d
```

3. **Truy cập Swagger:**
- http://localhost:8080/swagger

### 📋 **Lưu ý:**
- ⚠️ **Không commit** 2 files này lên git (chứa API keys)
- ✅ **Chỉ cần đặt đúng vị trí** là Docker sẽ tự động sử dụng
- ✅ **Không cần sửa gì** trong files này (đã config sẵn Gemini API)
- 🔄 **Hệ thống hiện dùng Gemini AI** thay vì OpenAI

---

## 🛑 Dừng / Xóa

```bash
# Dừng (giữ nguyên data DB)
docker compose down

# Dừng và xóa toàn bộ data DB (reset sạch)
docker compose down -v

# Xem logs backend realtime
docker compose logs -f backend

# Xem logs database
docker compose logs -f db
```

---

## 🔄 Cập nhật code mới từ BE team

Khi BE team push code mới, FE team pull về và build lại:

```bash
git pull
docker compose up --build -d
```

---

## ❓ Xử lý lỗi thường gặp

### Backend báo lỗi kết nối DB

```bash
# Kiểm tra DB đã healthy chưa
docker compose ps

# Xem log DB
docker compose logs db
```

### Port 8080 hoặc 5432 bị chiếm

Sửa trong file `.env`:

```env
BACKEND_PORT=8081
DB_PORT=5433
```

Rồi chạy lại: `docker compose up -d`

### Muốn xem log lỗi backend

```bash
docker compose logs backend --tail=50
```

---

## 📁 Cấu trúc file Docker

```
RAG-System/
├── Dockerfile            ← Build image ASP.NET Core (.NET 10 Preview)
├── docker-compose.yml    ← Orchestrate DB + Backend (updated với Gemini config)
├── .dockerignore         ← Loại bỏ file thừa khi build
├── .env.example          ← Template cấu hình (commit lên git)
├── .env                  ← Cấu hình thật (KHÔNG commit)
└── Database/
    └── scriptDB_final.sql ← Script khởi tạo DB tự động
```
