# Vyamit Frontend Startup Script
# Run this in PowerShell

Write-Host "📱 Starting Vyamit Frontend..." -ForegroundColor Green

# Navigate to frontend directory
Set-Location -Path "$PSScriptRoot\frontend_app"

# Get Flutter dependencies
Write-Host "📦 Getting Flutter dependencies..." -ForegroundColor Cyan
flutter pub get

Write-Host ""
Write-Host "Available devices:" -ForegroundColor Cyan
flutter devices

Write-Host ""
Write-Host "🎯 Starting Flutter app..." -ForegroundColor Green
Write-Host "   Select device from the list above" -ForegroundColor Gray
Write-Host "   Press 'r' for hot reload, 'R' for hot restart" -ForegroundColor Gray
Write-Host "   Press 'q' to quit" -ForegroundColor Gray
Write-Host ""

# Run Flutter app
flutter run
