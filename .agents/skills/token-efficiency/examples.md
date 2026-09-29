# PowerShell examples

Run these project examples from cemetery_app. Adapt paths and search terms to the task.

## Locate relevant code

```powershell
rg --files lib -g '*map*.dart'
rg -n -C 4 'class |Future<|Stream<' lib/services/map_feature_service.dart
Get-Content -LiteralPath 'lib/services/map_feature_service.dart' |
    Select-Object -Skip 40 -First 80
```

The excerpt covers lines 41 through 120. Expand to the full relevant function and callers before editing.

## Inspect changes

```powershell
git status --short
git diff --stat
git diff -- lib/services/map_feature_service.dart
```

Git diff omits untracked file contents; inspect new files separately.

## Inspect an existing log

```powershell
Get-Content -LiteralPath 'build.log' -Tail 80
Select-String -LiteralPath 'build.log' -Pattern 'error|exception|failed' -Context 3,6
```

Also check the original command's exit status. Keywords may miss failures or match benign messages.

## Capture analyzer status

```powershell
$analysisLog = Join-Path ([System.IO.Path]::GetTempPath()) ('cemetery-analyze-' + [guid]::NewGuid().ToString('N') + '.log')
flutter analyze *> $analysisLog
$analysisExitCode = $LASTEXITCODE
Write-Output "flutter analyze exit code: $analysisExitCode"
Write-Output "Full output: $analysisLog"
Get-Content -LiteralPath $analysisLog -Tail 80
exit $analysisExitCode
```

Run as a dedicated shell tool invocation: exit ends that invocation. If the tool yields a session handle, wait for completion. Investigate failures using the saved log.

## Select JSON fields

```powershell
$reportData = Get-Content -LiteralPath 'report.json' -Raw | ConvertFrom-Json
$reportData | Select-Object status, summary
```

Use actual schema fields. Missing fields are not evidence of success.
