@echo off
echo 🚀 Starting BE3 Backend for Mobile Development...
echo.
echo 📋 Configuration:
echo    - HTTP: http://0.0.0.0:5013 (accessible from mobile devices)
echo    - HTTPS: https://0.0.0.0:7258 (if needed)
echo    - Environment: Development
echo.
echo 🔧 Make sure to:
echo    1. Stop any existing backend process (Ctrl+C)
echo    2. Check firewall allows port 5013
echo    3. Mobile device is on same WiFi network
echo.
echo Starting backend from RAG.APIs directory...
cd RAG.APIs
dotnet run --launch-profile http