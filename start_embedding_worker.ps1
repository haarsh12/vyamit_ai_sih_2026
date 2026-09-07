# Runs the transactional outbox worker that writes pgvector embeddings for
# inventory and owner-approved verified customer names.

Set-Location -Path "$PSScriptRoot\backend_app"
& .\venv\Scripts\Activate.ps1
python -m app.workers.embeddings
