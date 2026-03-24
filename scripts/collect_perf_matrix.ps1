param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$InputPaths,

    [string]$Needle,

    [int]$FindAllLimit = 0,

    [int]$FindAllRangeLines = 0,

    [string[]]$States = @("clean", "edited"),

    [ValidateRange(1, 1000)]
    [int]$Repeats = 2,

    [ValidateRange(0, 3600)]
    [int]$WaitSecs = 20,

    [string]$SeedEdit = "[probe]`n",

    [string]$MatrixLabel = "",

    [string]$OutputJsonl = "target\perf-matrix.jsonl",

    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

if ($FindAllLimit -gt 0 -and [string]::IsNullOrWhiteSpace($Needle)) {
    throw "--FindAllLimit requires -Needle."
}

if ($FindAllRangeLines -gt 0 -and $FindAllLimit -le 0) {
    throw "--FindAllRangeLines requires -FindAllLimit."
}

$States = @(
    $States |
        ForEach-Object { $_ -split "," } |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

foreach ($state in $States) {
    if ($state -notin @("clean", "edited")) {
        throw "Unsupported state '$state'. Expected clean and/or edited."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $repoRoot $OutputJsonl
$outputDir = Split-Path -Parent $outputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}
if (Test-Path $outputPath) {
    Remove-Item -Force $outputPath
}

$perfProbeExe = Join-Path $repoRoot "target\debug\examples\perf_probe.exe"

Push-Location $repoRoot
try {
    if (-not $SkipBuild -or -not (Test-Path $perfProbeExe)) {
        cargo build --example perf_probe
        if ($LASTEXITCODE -ne 0) {
            throw "cargo build --example perf_probe failed."
        }
    }

    if (-not (Test-Path $perfProbeExe)) {
        throw "perf_probe binary was not found at $perfProbeExe"
    }

    foreach ($inputPath in $InputPaths) {
        $resolvedInput = Resolve-Path $inputPath
        $inputFullPath = $resolvedInput.Path
        $inputLabel = Split-Path -Leaf $inputFullPath

        foreach ($state in $States) {
            for ($runIndex = 1; $runIndex -le $Repeats; $runIndex++) {
                $args = @(
                    $inputFullPath,
                    "--json",
                    "--wait-secs",
                    $WaitSecs.ToString()
                )

                if (-not [string]::IsNullOrWhiteSpace($Needle)) {
                    $args += @("--needle", $Needle)
                }
                if ($FindAllLimit -gt 0) {
                    $args += @("--find-all-limit", $FindAllLimit.ToString())
                }
                if ($FindAllRangeLines -gt 0) {
                    $args += @("--find-all-range-lines", $FindAllRangeLines.ToString())
                }
                if ($state -eq "edited") {
                    $args += @("--seed-edit", $SeedEdit)
                }

                Write-Host ("[{0}/{1}] state={2} file={3}" -f $runIndex, $Repeats, $state, $inputLabel)

                $rawOutput = & $perfProbeExe @args 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "perf_probe failed for state=$state file=$inputFullPath"
                }

                $jsonLine = $rawOutput | Where-Object { $_.TrimStart().StartsWith("{") } | Select-Object -Last 1
                if (-not $jsonLine) {
                    throw "perf_probe did not emit JSON for state=$state file=$inputFullPath"
                }

                $record = $jsonLine | ConvertFrom-Json
                $record | Add-Member -NotePropertyName "matrix_state" -NotePropertyValue $state
                $record | Add-Member -NotePropertyName "matrix_run" -NotePropertyValue $runIndex
                $record | Add-Member -NotePropertyName "matrix_input_label" -NotePropertyValue $inputLabel
                $record | Add-Member -NotePropertyName "matrix_wait_secs" -NotePropertyValue $WaitSecs
                $record | Add-Member -NotePropertyName "matrix_label" -NotePropertyValue $MatrixLabel

                ($record | ConvertTo-Json -Compress) | Add-Content -Path $outputPath
            }
        }
    }
}
finally {
    Pop-Location
}

Write-Host ("Wrote JSONL matrix to {0}" -f $outputPath)
