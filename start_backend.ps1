# Vyamit Backend Startup Script
# Run this in PowerShell

Write-Host "🚀 Starting Vyamit Backend..." -ForegroundColor Green

# Navigate to backend directory
Set-Location -Path "$PSScriptRoot\backend_app"

# Activate virtual environment
Write-Host "📦 Activating virtual environment..." -ForegroundColor Cyan
& .\venv\Scripts\Activate.ps1

# Check if .env exists
if (-not (Test-Path ".env")) {
    Write-Host "⚠️  Warning: .env file not found!" -ForegroundColor Yellow
    Write-Host "   Copy .env.example to .env and configure it." -ForegroundColor Yellow
    exit 1
}

# Keep the database schema aligned with the application before accepting traffic.
# This prevents a new API build from querying columns that are not yet present.
Write-Host "🗃️  Applying database migrations..." -ForegroundColor Cyan
python -m alembic upgrade head
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Database migration failed. Backend was not started." -ForegroundColor Red
    exit $LASTEXITCODE
}

# Start FastAPI server
Write-Host "🌐 Starting FastAPI server on http://localhost:8000..." -ForegroundColor Green
Write-Host "   Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
