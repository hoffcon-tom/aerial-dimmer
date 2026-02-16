param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-JpegFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Get-ChildItem -Path $Path -File | Where-Object {
        $_.Extension -match '^\.(jpe?g)$' -and $_.Name -notlike '*.tmp-aerialfade.jpg'
    }
}

function Resolve-TargetFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawInput
    )

    $directDir = Resolve-Path -LiteralPath $RawInput -ErrorAction SilentlyContinue
    if ($directDir) {
        $item = Get-Item -LiteralPath $directDir.Path
        if ($item.PSIsContainer) {
            return $item.FullName
        }

        if ($item.Extension -ieq '.dwg') {
            $folder = Join-Path -Path $item.DirectoryName -ChildPath $item.BaseName
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                throw "DWG found but matching image folder not found: $folder"
            }
            return (Resolve-Path -LiteralPath $folder).Path
        }

        throw "Input file is not a DWG: $($item.FullName)"
    }

    if ([System.IO.Path]::GetExtension($RawInput) -eq '') {
        $dwgCandidate = "$RawInput.dwg"
        $dwgPath = Resolve-Path -LiteralPath $dwgCandidate -ErrorAction SilentlyContinue
        if ($dwgPath) {
            $dwgItem = Get-Item -LiteralPath $dwgPath.Path
            $folder = Join-Path -Path $dwgItem.DirectoryName -ChildPath $dwgItem.BaseName
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                throw "DWG found but matching image folder not found: $folder"
            }
            return (Resolve-Path -LiteralPath $folder).Path
        }
    }

    throw "Input path not found as folder or DWG: $RawInput"
}

function Ensure-MagickAvailable {
    $cmd = Get-Command -Name magick -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw 'ImageMagick command `magick` not found in PATH.'
    }
}

function Format-Clock {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Seconds
    )

    [TimeSpan]::FromSeconds([Math]::Max(0, [Math]::Round($Seconds))).ToString('hh\:mm\:ss')
}

$targetFolder = Resolve-TargetFolder -RawInput $InputPath
$jpgFiles = @(Get-JpegFiles -Path $targetFolder)
if (-not $jpgFiles) {
    throw "Invalid target folder. No JPG/JPEG files found in: $targetFolder"
}

$originalDir = Join-Path -Path $targetFolder -ChildPath 'original'
$normalizeAction = $Action.Trim().ToLowerInvariant()
$restoreRequested = ($normalizeAction -eq 'restore' -or $normalizeAction -eq '0')

if ($restoreRequested) {
    if (-not (Test-Path -LiteralPath $originalDir -PathType Container)) {
        throw "Cannot restore. Backup folder not found: $originalDir"
    }

    $originalJpgFiles = @(Get-JpegFiles -Path $originalDir)
    if (-not $originalJpgFiles) {
        throw "Cannot restore. No JPG/JPEG files found in backup folder: $originalDir"
    }

    foreach ($src in $originalJpgFiles) {
        $dst = Join-Path -Path $targetFolder -ChildPath $src.Name
        Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
    }

    Write-Host "Restored $($originalJpgFiles.Count) image(s) from backup in: $targetFolder"
    exit 0
}

[int]$fadePercent = 0
if (-not [int]::TryParse($Action, [ref]$fadePercent)) {
    throw "Fade must be an integer 1-100, 0, or 'restore'. Received: $Action"
}
if ($fadePercent -lt 1 -or $fadePercent -gt 100) {
    throw "Fade percent out of range: $fadePercent. Use 1-100, 0, or 'restore'."
}

if (-not (Test-Path -LiteralPath $originalDir -PathType Container)) {
    New-Item -ItemType Directory -Path $originalDir | Out-Null
    foreach ($src in $jpgFiles) {
        Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $originalDir $src.Name)
    }
    Write-Host "Created backup in: $originalDir"
}

Ensure-MagickAvailable

$sourceJpgFiles = @(Get-JpegFiles -Path $originalDir)
if (-not $sourceJpgFiles) {
    throw "Backup folder exists but has no JPG/JPEG files: $originalDir"
}

$totalImages = $sourceJpgFiles.Count
$showProgress = $totalImages -gt 10
$processed = 0
$timer = $null
if ($showProgress) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
}

foreach ($src in $sourceJpgFiles) {
    $processed++
    if ($showProgress) {
        $elapsedSeconds = $timer.Elapsed.TotalSeconds
        $secondsPerImage = if ($processed -gt 0) { $elapsedSeconds / $processed } else { 0 }
        $remainingSeconds = $secondsPerImage * ($totalImages - $processed)
        $percentComplete = [int](($processed / $totalImages) * 100)
        $status = "$processed / $totalImages | elapsed $(Format-Clock -Seconds $elapsedSeconds) | remaining $(Format-Clock -Seconds $remainingSeconds)"
        Write-Progress -Activity "Fading aerial images" -Status $status -PercentComplete $percentComplete
    }

    $dstPath = Join-Path -Path $targetFolder -ChildPath $src.Name
    $tmpOut = Join-Path -Path $targetFolder -ChildPath ($src.BaseName + '.tmp-aerialfade-' + [Guid]::NewGuid().ToString('N') + '.jpg')
    try {
        & magick "$($src.FullName)" -fill white -colorize "${fadePercent}%" "$tmpOut"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmpOut -PathType Leaf)) {
            throw "ImageMagick failed processing: $($src.FullName)"
        }

        Move-Item -LiteralPath $tmpOut -Destination $dstPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $tmpOut -PathType Leaf) {
            Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($showProgress) {
    $timer.Stop()
    Write-Progress -Activity "Fading aerial images" -Completed
}

Write-Host "Faded $($sourceJpgFiles.Count) image(s) to ${fadePercent}% in: $targetFolder"

