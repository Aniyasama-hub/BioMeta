param(
    [string]$Rscript,
    [ValidateRange(1024, 65515)][int]$Port = 7878,
    [switch]$NoBrowser
)
# ASCII source intentionally supports Windows PowerShell 5.1 without a BOM.
$ErrorActionPreference = 'Stop'
$appRoot = Join-Path $PSScriptRoot 'app'
$logRoot = Join-Path $PSScriptRoot 'logs'
$logFile = $null
$oldLocale = $env:LC_ALL
try {
    $settingsPath = Join-Path $appRoot 'results/toolbox/settings.json'
    if (-not $PSBoundParameters.ContainsKey('Rscript') -and (Test-Path -LiteralPath $settingsPath)) {
        $settings = Get-Content -LiteralPath $settingsPath -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($settings.rscript) { $Rscript = $settings.rscript }
    }
    if (-not $Rscript) {
        $command = Get-Command Rscript.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $Rscript = $command.Source }
    }
    if (-not $Rscript) {
        $locations = @($env:R_HOME)
        foreach ($key in @('HKCU:\SOFTWARE\R-core\R', 'HKLM:\SOFTWARE\R-core\R',
                           'HKLM:\SOFTWARE\WOW6432Node\R-core\R')) {
            $installation = Get-ItemProperty -LiteralPath $key -Name InstallPath -ErrorAction SilentlyContinue
            if ($installation.InstallPath) { $locations += $installation.InstallPath }
        }
        foreach ($location in $locations) {
            if (-not $location) { continue }
            $candidate = Join-Path $location 'bin\Rscript.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $Rscript = $candidate; break }
        }
    }
    if (-not $Rscript -or -not (Test-Path -LiteralPath $Rscript -PathType Leaf)) {
        throw "Rscript not found: $Rscript. Use -Rscript to select an installed R."
    }
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $logFile = Join-Path $logRoot ('startup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    $selectedPort = 0
    for ($candidate = $Port; $candidate -lt ($Port + 20); $candidate++) {
        $listener = $null
        try {
            $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback),$candidate
            $listener.Start()
            $selectedPort = $candidate
        }
        catch { }
        finally { if ($listener) { $listener.Stop() } }
        if ($selectedPort -ne 0) { break }
    }
    if ($selectedPort -eq 0) { throw 'No free local port was found.' }
    $env:LC_ALL = 'English_United States.utf8'
    Write-Host 'BioWorkbench - local R analysis toolbox'
    Write-Host "Address: http://127.0.0.1:$selectedPort"
    Write-Host "Startup log: $logFile"
    Write-Host 'Keep this window open. Press Ctrl+C to stop the service.'
    $browser = if ($NoBrowser) { 'FALSE' } else { 'TRUE' }
    $runArgs = @('--vanilla', (Join-Path $appRoot 'start.R'), $appRoot,
                  [string]$selectedPort, $browser, $logFile)
    & $Rscript @runArgs
    if ($LASTEXITCODE -ne 0) { throw "R exited with code $LASTEXITCODE." }
}
catch {
    Write-Host ''
    Write-Host ('STARTUP FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    if ($logFile -and (Test-Path -LiteralPath $logFile)) {
        Get-Content -LiteralPath $logFile -Tail 35 -Encoding UTF8 | Write-Host
    }
    exit 1
}
finally { $env:LC_ALL = $oldLocale }
