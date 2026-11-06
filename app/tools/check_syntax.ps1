param(
    [string]$Rscript = 'Rscript.exe',
    [string]$Python = 'python'
)
# 只解析源码；不source脚本、不调用分析、不生成科研结果。
$ErrorActionPreference = 'Stop'
$workbenchRoot = Split-Path -Parent $PSScriptRoot
Push-Location $workbenchRoot
$previousLocale = $env:LC_ALL
try {
    $env:LC_ALL = 'English_United States.utf8'
    & $Rscript --vanilla -e 'files <- list.files(".", pattern="[.]R$", recursive=TRUE, full.names=TRUE); files <- files[!grepl("/results/", files)]; for (f in files) { parse(file=f, encoding="UTF-8"); cat(f, "OK\n") }'
    if ($LASTEXITCODE -ne 0) { throw 'R语法检查失败。' }
    & $Python -c 'import ast,pathlib; files=[p for p in pathlib.Path(".").rglob("*.py") if "results" not in p.parts]; [(ast.parse(p.read_text(encoding="utf-8-sig"), filename=str(p)), print(str(p)+" OK")) for p in files]'
    if ($LASTEXITCODE -ne 0) { throw 'Python语法检查失败。' }
    Get-ChildItem -LiteralPath $workbenchRoot -Filter '*.ps1' -Recurse | ForEach-Object {
        $parseTokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName, [ref]$parseTokens, [ref]$parseErrors
        )
        if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
        Write-Output "$($_.Name) OK"
    }
}
finally {
    $env:LC_ALL = $previousLocale
    Pop-Location
}
