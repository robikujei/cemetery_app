param(
    [ValidateSet('admin', 'users')]
    [string]$Audience = 'users',
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    flutter build web --release --dart-define="APP_AUDIENCE=$Audience"
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
