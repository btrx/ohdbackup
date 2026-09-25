<#
.SYNOPSIS
Bulk-optimizes the museum's imported video files while preserving filenames and Unity GUIDs.

.DESCRIPTION
By default this script only reports what it would do. Pass -Apply to transcode files.
Original videos are copied to a timestamped folder under _video_backup before replacement.
The matching .meta files are never changed, so scene/prefab references remain valid.

.EXAMPLE
.\Tools\Optimize-VideoAssets.ps1

.EXAMPLE
.\Tools\Optimize-VideoAssets.ps1 -Apply -Profile Balanced
#>
[CmdletBinding()]
param(
    [ValidateSet('Smallest', 'Balanced', 'HighQuality')]
    [string]$Profile = 'Balanced',

    [string]$AssetDirectory = (Join-Path $PSScriptRoot '..\Assets\arvideo'),

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$profiles = @{
    Smallest = @{
        MaxLongEdge = 960
        Crf = 26
        Preset = 'slow'
        AudioKbps = 64
        Description = '960p long edge, CRF 26, 64 kbps audio'
    }
    Balanced = @{
        MaxLongEdge = 1280
        Crf = 23
        Preset = 'slow'
        AudioKbps = 96
        Description = '720p-class (1280px long edge), CRF 23, 96 kbps audio'
    }
    HighQuality = @{
        MaxLongEdge = 1920
        Crf = 20
        Preset = 'slow'
        AudioKbps = 128
        Description = '1080p-class (1920px long edge), CRF 20, 128 kbps audio'
    }
}

function Resolve-Executable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $resolved = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        throw "$Label was not found. Install FFmpeg and ensure '$Command' is on PATH."
    }

    return $resolved.Source
}

function Get-MediaInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FfprobePath,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $json = & $FfprobePath -v error `
        -show_entries 'format=duration:stream=codec_type,width,height' `
        -of json $Path 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe could not read '$Path': $($json -join [Environment]::NewLine)"
    }

    $data = ($json -join [Environment]::NewLine) | ConvertFrom-Json
    $video = $data.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    if ($null -eq $video) {
        throw "No video stream was found in '$Path'."
    }

    $audioStreams = @($data.streams | Where-Object { $_.codec_type -eq 'audio' })

    return [pscustomobject]@{
        Width = [int]$video.width
        Height = [int]$video.height
        DurationSeconds = [double]$data.format.duration
        AudioStreamCount = $audioStreams.Count
    }
}

function Get-EvenTargetSize {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Width,
        [Parameter(Mandatory = $true)]
        [int]$Height,
        [Parameter(Mandatory = $true)]
        [int]$MaxLongEdge
    )

    $longEdge = [Math]::Max($Width, $Height)
    $scale = [Math]::Min(1.0, $MaxLongEdge / [double]$longEdge)
    $targetWidth = [Math]::Max(2, 2 * [Math]::Floor(($Width * $scale) / 2))
    $targetHeight = [Math]::Max(2, 2 * [Math]::Floor(($Height * $scale) / 2))

    return [pscustomobject]@{
        Width = $targetWidth
        Height = $targetHeight
    }
}

function Get-AppliedVideoRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $backupRoot = Join-Path $RepositoryRoot '_video_backup'
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        return @()
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $manifests = @(Get-ChildItem -LiteralPath $backupRoot -Recurse -File -Filter 'optimization-manifest.json')
    foreach ($manifestFile in $manifests) {
        try {
            $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
            $manifestProfile = $manifest.profile
            foreach ($file in @($manifest.files)) {
                if ($null -ne $file.fileName -and $null -ne $file.sha256) {
                    # The profile is stored at the manifest root, not per file.
                    # Copy it onto the record so callers can filter on .profile
                    # (StrictMode forbids reading missing properties).
                    $records.Add([pscustomobject]@{
                        fileName = $file.fileName
                        sha256   = $file.sha256
                        backupFile = $file.backupFile
                        profile  = $manifestProfile
                    })
                }
            }
        }
        catch {
            Write-Warning "Could not read optimization manifest '$($manifestFile.FullName)': $($_.Exception.Message)"
        }
    }

    return $records.ToArray()
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$assetPath = [System.IO.Path]::GetFullPath($AssetDirectory)
$ffmpegPath = Resolve-Executable -Command 'ffmpeg' -Label 'ffmpeg'
$ffprobePath = Resolve-Executable -Command 'ffprobe' -Label 'ffprobe'
$settings = $profiles[$Profile]

if (-not (Test-Path -LiteralPath $assetPath -PathType Container)) {
    throw "Video asset directory does not exist: $assetPath"
}

$videos = @(Get-ChildItem -LiteralPath $assetPath -File -Filter '*.mp4' | Sort-Object Name)
if ($videos.Count -eq 0) {
    Write-Host "No MP4 files found in $assetPath."
    return
}

$sourceTotalBytes = [double](($videos | Measure-Object -Property Length -Sum).Sum)
Write-Host "Profile: $Profile - $($settings.Description)"
Write-Host "Videos: $($videos.Count), source size: $([Math]::Round($sourceTotalBytes / 1MB, 2)) MB"
Write-Host "ffmpeg: $ffmpegPath"

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Dry run only. Add -Apply to create backups and replace the videos.'
    $videos | Select-Object Name, @{Name='SourceMB';Expression={[Math]::Round($_.Length / 1MB, 2)}} |
        Format-Table -AutoSize
    return
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDirectory = Join-Path $repositoryRoot "_video_backup\$Profile-$timestamp"
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
Write-Host "Backup directory: $backupDirectory"
$appliedRecords = @(Get-AppliedVideoRecords -RepositoryRoot $repositoryRoot)

$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "ohdmuseum-video-opt-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

try {
    foreach ($video in $videos) {
        $currentHash = (Get-FileHash -LiteralPath $video.FullName -Algorithm SHA256).Hash
        $priorRecord = $appliedRecords | Where-Object {
            $_.profile -eq $Profile -and
            $_.fileName -eq $video.Name -and
            $_.sha256 -eq $currentHash
        } | Select-Object -First 1

        if ($null -ne $priorRecord) {
            $results.Add([pscustomobject]@{
                File = $video.Name
                Status = 'Skipped (already optimized)'
                SourceMB = [Math]::Round($video.Length / 1MB, 2)
                OptimizedMB = [Math]::Round($video.Length / 1MB, 2)
                SavedMB = 0
                Resolution = ''
                Sha256 = $currentHash
                BackupFile = $null
            })
            continue
        }

        $temporaryOutput = Join-Path $tempDirectory "$($video.BaseName)-optimized.mp4"
        $backupOutput = Join-Path $backupDirectory $video.Name

        try {
            $sourceInfo = Get-MediaInfo -FfprobePath $ffprobePath -Path $video.FullName
            $target = Get-EvenTargetSize -Width $sourceInfo.Width -Height $sourceInfo.Height -MaxLongEdge $settings.MaxLongEdge

            $arguments = @(
                '-hide_banner', '-loglevel', 'error', '-y',
                '-i', $video.FullName,
                '-map', '0:v:0',
                '-map', '0:a?',
                '-map_metadata', '0',
                '-vf', "scale=$($target.Width):$($target.Height)",
                '-c:v', 'libx264',
                '-preset', $settings.Preset,
                '-crf', [string]$settings.Crf,
                '-pix_fmt', 'yuv420p',
                '-profile:v', 'high',
                '-c:a', 'aac',
                '-b:a', "$($settings.AudioKbps)k",
                '-movflags', '+faststart',
                $temporaryOutput
            )

            & $ffmpegPath @arguments
            if ($LASTEXITCODE -ne 0) {
                throw "ffmpeg exited with code $LASTEXITCODE."
            }

            $optimizedInfo = Get-MediaInfo -FfprobePath $ffprobePath -Path $temporaryOutput
            $optimizedFile = Get-Item -LiteralPath $temporaryOutput
            $sourceFile = Get-Item -LiteralPath $video.FullName
            $durationDifference = [Math]::Abs($optimizedInfo.DurationSeconds - $sourceInfo.DurationSeconds)
            $maxDurationDifference = [Math]::Max(1.0, $sourceInfo.DurationSeconds * 0.02)

            if ($optimizedInfo.Width -ne $target.Width -or $optimizedInfo.Height -ne $target.Height) {
                throw "Unexpected output resolution $($optimizedInfo.Width)x$($optimizedInfo.Height); expected $($target.Width)x$($target.Height)."
            }
            if ($durationDifference -gt $maxDurationDifference) {
                throw "Output duration differs by $([Math]::Round($durationDifference, 2)) seconds."
            }
            if ($optimizedInfo.AudioStreamCount -ne $sourceInfo.AudioStreamCount) {
                throw 'The optimized file does not contain the same number of audio streams.'
            }

            $savedBytes = $sourceFile.Length - $optimizedFile.Length
            if ($savedBytes -le 0) {
                $results.Add([pscustomobject]@{
                    File = $video.Name
                    Status = 'Skipped (not smaller)'
                    SourceMB = [Math]::Round($sourceFile.Length / 1MB, 2)
                    OptimizedMB = [Math]::Round($optimizedFile.Length / 1MB, 2)
                    SavedMB = 0
                    Resolution = "$($optimizedInfo.Width)x$($optimizedInfo.Height)"
                })
                continue
            }

            Copy-Item -LiteralPath $video.FullName -Destination $backupOutput -Force
            try {
                [System.IO.File]::Copy($temporaryOutput, $video.FullName, $true)
            }
            catch {
                Copy-Item -LiteralPath $backupOutput -Destination $video.FullName -Force
                throw
            }

            $results.Add([pscustomobject]@{
                File = $video.Name
                Status = 'Optimized'
                SourceMB = [Math]::Round($sourceFile.Length / 1MB, 2)
                OptimizedMB = [Math]::Round($optimizedFile.Length / 1MB, 2)
                SavedMB = [Math]::Round($savedBytes / 1MB, 2)
                Resolution = "$($optimizedInfo.Width)x$($optimizedInfo.Height)"
                Sha256 = (Get-FileHash -LiteralPath $video.FullName -Algorithm SHA256).Hash
                BackupFile = $backupOutput
            })
        }
        catch {
            $message = "$($video.Name): $($_.Exception.Message)"
            $failed.Add($message)
            Write-Error $message
        }
        finally {
            if (Test-Path -LiteralPath $temporaryOutput) {
                Remove-Item -LiteralPath $temporaryOutput -Force
            }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
}

Write-Host ''
$results | Format-Table -AutoSize

$optimizedResults = @($results | Where-Object Status -EQ 'Optimized')
$sourceBytes = [double](($optimizedResults | Measure-Object -Property SourceMB -Sum).Sum)
$optimizedBytes = [double](($optimizedResults | Measure-Object -Property OptimizedMB -Sum).Sum)
$savedBytes = [double](($optimizedResults | Measure-Object -Property SavedMB -Sum).Sum)
$savedPercent = if ($sourceBytes -gt 0) { [Math]::Round(($savedBytes / $sourceBytes) * 100, 1) } else { 0 }

$manifestFiles = @(
    foreach ($result in $optimizedResults) {
        [ordered]@{
            fileName = $result.File
            sha256 = $result.Sha256
            backupFile = $result.BackupFile
        }
    }
)
$manifest = [ordered]@{
    version = 1
    profile = $Profile
    appliedAtUtc = [DateTime]::UtcNow.ToString('o')
    files = $manifestFiles
}
$manifestPath = Join-Path $backupDirectory 'optimization-manifest.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), $utf8NoBom)

Write-Host "Optimized $($optimizedResults.Count) video(s)."
Write-Host "Saved $([Math]::Round($savedBytes, 2)) MB ($savedPercent%)."
Write-Host "Originals: $backupDirectory"
Write-Host "Manifest: $manifestPath"

if ($failed.Count -gt 0) {
    Write-Error "$($failed.Count) video(s) failed. See the messages above."
    exit 1
}
