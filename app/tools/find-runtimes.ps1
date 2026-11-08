param(
  [ValidateSet('R','Python','RStudio')][string]$Kind,
  [string]$Configured = '',
  [string]$Current = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$found = [System.Collections.Generic.List[object]]::new()
$seen = @{}
$exeName = @{ R='Rscript.exe'; Python='python.exe'; RStudio='rstudio.exe' }[$Kind]
function Add-Candidate([string]$Path, [string]$Source) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  if ((Split-Path -Leaf $Path) -ine $exeName -or $Path -match '\\Microsoft\\WindowsApps\\') { return }
  $absolute = (Resolve-Path -LiteralPath $Path).ProviderPath
  $key = $absolute.ToLowerInvariant()
  if ($Kind -eq 'R') { $key = $key -replace '\\bin\\(x64\\)?rscript.exe$', '' }
  if ($seen.ContainsKey($key)) { return }
  $seen[$key] = $true
  $fileVersion = if ($Kind -eq 'RStudio') { [Diagnostics.FileVersionInfo]::GetVersionInfo($absolute).ProductVersion } else { '' }
  $found.Add([pscustomobject]@{path=$absolute;source=$Source;file_version=$fileVersion})
}
function Inspect-Directory([string]$Directory, [string]$Source, [int]$Depth = 0) {
  if (-not $Directory -or -not (Test-Path -LiteralPath $Directory -PathType Container)) { return }
  foreach ($relative in @($exeName, "bin\$exeName", "bin\x64\$exeName", "Scripts\$exeName", "resources\app\bin\$exeName")) {
    Add-Candidate (Join-Path $Directory $relative) $Source
  }
  if ($Depth -ge 3) { return }
  foreach ($child in @(Get-ChildItem -LiteralPath $Directory -Directory -ErrorAction SilentlyContinue)) {
    if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
    if ($child.Name -match '^(R($|[-0-9.])|python|anaconda|miniconda|conda|envs$|rstudio|posit|programs$|tools$|software$|apps$)' -or (Split-Path -Leaf $Directory) -eq 'envs') {
      Inspect-Directory $child.FullName $Source ($Depth + 1)
    }
  }
}
Add-Candidate $Configured 'Saved configuration'
Add-Candidate $Current 'Current process'
foreach ($command in @(Get-Command $exeName -All -CommandType Application -ErrorAction SilentlyContinue)) {
  Add-Candidate $command.Source 'PATH'
}
foreach ($variable in @('R_HOME','PYTHONHOME','CONDA_PREFIX','VIRTUAL_ENV')) {
  Inspect-Directory ([Environment]::GetEnvironmentVariable($variable)) "Environment: $variable"
}
foreach ($hive in @('HKCU:\Software','HKLM:\Software','HKCU:\Software\WOW6432Node','HKLM:\Software\WOW6432Node')) {
  if ($Kind -eq 'R') {
    foreach ($branch in @('R-core\R','R-core\R64')) {
      $key = Join-Path $hive $branch
      foreach ($item in @($key) + @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSPath)) {
        $entry = Get-ItemProperty -LiteralPath $item -ErrorAction SilentlyContinue
        Inspect-Directory $entry.InstallPath 'Windows R registry'
      }
    }
  }
  if ($Kind -eq 'Python') {
    $key = Join-Path $hive 'Python\PythonCore'
    foreach ($item in @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue)) {
      $entry = Get-ItemProperty -LiteralPath (Join-Path $item.PSPath 'InstallPath') -ErrorAction SilentlyContinue
      Add-Candidate $entry.ExecutablePath 'Windows Python registry'
      Inspect-Directory $entry.'(default)' 'Windows Python registry'
    }
  }
  $appPath = Join-Path $hive "Microsoft\Windows\CurrentVersion\App Paths\$exeName"
  $entry = Get-ItemProperty -LiteralPath $appPath -ErrorAction SilentlyContinue
  Add-Candidate $entry.'(default)' 'Windows App Paths'
}
foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'), $env:USERPROFILE)) {
  Inspect-Directory $base 'Standard/user installations'
}
foreach ($drive in @(Get-PSDrive -PSProvider FileSystem)) {
  if ($drive.DisplayRoot -match '^\\\\' -or $drive.Root -match '^\\\\') { continue }
  Inspect-Directory $drive.Root 'Drive-root runtime directories'
}
if ($Kind -eq 'Python') {
  $launcher = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($launcher) {
    foreach ($line in @(& $launcher.Source -0p 2>$null)) {
      if ($line -match '([A-Za-z]:\\.+python.exe)\s*$') { Add-Candidate $Matches[1] 'Python launcher' }
    }
  }
}
ConvertTo-Json -InputObject @($found.ToArray()) -Depth 4 -Compress
