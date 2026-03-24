param(
    [string]$InputJsonl = "target\perf-matrix.jsonl",
    [string]$OutputMarkdown = "target\perf-matrix-summary.md"
)

$ErrorActionPreference = "Stop"
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Format-InvariantNumber {
    param(
        [double]$Value
    )

    return $Value.ToString("0.000", $InvariantCulture)
}

function Get-StatsRow {
    param(
        [object[]]$Values
    )

    $filtered = @($Values | Where-Object { $_ -ne $null })
    if ($filtered.Count -eq 0) {
        return @{
            median = "-"
            min = "-"
            max = "-"
        }
    }

    $sorted = @($filtered | Sort-Object)
    $count = $sorted.Count
    if ($count % 2 -eq 1) {
        $median = [double]$sorted[[int]($count / 2)]
    }
    else {
        $median = ([double]$sorted[($count / 2) - 1] + [double]$sorted[$count / 2]) / 2.0
    }

    return @{
        median = (Format-InvariantNumber ([double]$median))
        min = (Format-InvariantNumber ([double]$sorted[0]))
        max = (Format-InvariantNumber ([double]$sorted[$count - 1]))
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$inputPath = Join-Path $repoRoot $InputJsonl
$outputPath = Join-Path $repoRoot $OutputMarkdown

if (-not (Test-Path $inputPath)) {
    throw "Input JSONL not found: $inputPath"
}

$rows = Get-Content $inputPath |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_ | ConvertFrom-Json }

if ($rows.Count -eq 0) {
    throw "Input JSONL is empty: $inputPath"
}

$groups = $rows | Group-Object {
    "{0}|{1}|{2}|{3}" -f $_.matrix_input_label, $_.matrix_state, $_.backing, $_.matrix_label
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Perf Matrix Summary")
$lines.Add("")
$lines.Add(('Source: `{0}`' -f $InputJsonl))
$lines.Add("")
$lines.Add('| input | label | state | backing | runs | open ms | viewport ms | next ms | prev ms | find_all ms |')
$lines.Add('| --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- |')

foreach ($group in ($groups | Sort-Object Name)) {
    $parts = $group.Name.Split('|', 4)
    $inputLabel = $parts[0]
    $state = $parts[1]
    $backing = $parts[2]
    $matrixLabel = $parts[3]
    if ([string]::IsNullOrWhiteSpace($matrixLabel)) {
        $matrixLabel = "-"
    }

    $openStats = Get-StatsRow ($group.Group | ForEach-Object { $_.open_ms })
    $viewportStats = Get-StatsRow ($group.Group | ForEach-Object { $_.viewport_ms })
    $nextStats = Get-StatsRow ($group.Group | ForEach-Object { $_.next_ms })
    $prevStats = Get-StatsRow ($group.Group | ForEach-Object { $_.prev_ms })
    $findAllStats = Get-StatsRow ($group.Group | ForEach-Object { $_.find_all_ms })

    $lines.Add(
        ('| {0} | {1} | {2} | {3} | {4} | {5} [{6}-{7}] | {8} [{9}-{10}] | {11} [{12}-{13}] | {14} [{15}-{16}] | {17} [{18}-{19}] |' -f
            $inputLabel,
            $matrixLabel,
            $state,
            $backing,
            $group.Count,
            $openStats.median, $openStats.min, $openStats.max,
            $viewportStats.median, $viewportStats.min, $viewportStats.max,
            $nextStats.median, $nextStats.min, $nextStats.max,
            $prevStats.median, $prevStats.min, $prevStats.max,
            $findAllStats.median, $findAllStats.min, $findAllStats.max
        )
    )
}

$outputDir = Split-Path -Parent $outputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$lines | Set-Content -Path $outputPath
Write-Host ("Wrote markdown summary to {0}" -f $outputPath)
