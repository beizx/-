param(
    [switch]$DebugBuild
)

$ErrorActionPreference = 'Stop'

$source = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$asciiPattern = '^[\x00-\x7F]+$'

$pubspec = Get-Content -Raw (Join-Path $source 'pubspec.yaml')
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { '0.0.0' }

if ($source -match $asciiPattern) {
    $staging = $source
} else {
    # A real ASCII directory is required: junctions and mapped drives still
    # resolve back to the Chinese path inside Flutter's AOT snapshotter.
    $staging = Join-Path $env:LOCALAPPDATA 'Temp\translation_app_build_ascii'
    if ($staging -notmatch $asciiPattern) {
        $staging = 'C:\translation_app_build_ascii'
    }

    Write-Host "Project path contains non-ASCII characters."
    Write-Host "Staging to: $staging"

    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    $arguments = @(
        $source,
        $staging,
        '/MIR',
        '/XD', 'build', '.dart_tool', '.git', '.idea', 'artifacts',
        '/XF', 'flutter_*.log',
        '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP'
    )
    & robocopy @arguments | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Robocopy failed with exit code $LASTEXITCODE"
    }
}

Push-Location $staging
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }

    if ($DebugBuild) {
        & flutter build apk --debug
    } else {
        & flutter build apk --release
    }
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }

    $apkName = if ($DebugBuild) { 'app-debug.apk' } else { 'app-release.apk' }
    $apk = Join-Path $staging "build\app\outputs\flutter-apk\$apkName"
    if (-not (Test-Path $apk)) {
        throw "APK not found: $apk"
    }

    $outputDir = Join-Path $source 'artifacts'
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $artifactName = if ($DebugBuild) {
        "BeizxReader-v$version-debug.apk"
    } else {
        "BeizxReader-v$version.apk"
    }
    $artifact = Join-Path $outputDir $artifactName
    Copy-Item -LiteralPath $apk -Destination $artifact -Force

    # Keep the conventional Flutter output path available in the real project.
    $projectOutput = Join-Path $source 'build\app\outputs\flutter-apk'
    New-Item -ItemType Directory -Force -Path $projectOutput | Out-Null
    Copy-Item -LiteralPath $apk -Destination (Join-Path $projectOutput $apkName) -Force

    Write-Host ''
    Write-Host "APK: $artifact" -ForegroundColor Green
} finally {
    Pop-Location
}
