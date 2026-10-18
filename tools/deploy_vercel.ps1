param([switch]$Preview)

$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    # The primary web deployment is the administrator portal. Visitor and
    # gate-officer portals are built from their dedicated entrypoints.
    flutter build web --release --target=lib/main_admin.dart
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }

    if ($Preview) {
        npx --yes vercel@latest deploy
    } else {
        npx --yes vercel@latest deploy --prod
    }
    if ($LASTEXITCODE -ne 0) { throw 'Vercel deployment failed.' }
} finally {
    Pop-Location
}
