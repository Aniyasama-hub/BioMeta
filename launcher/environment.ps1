function Find-BiometaR {
  param([string]$Root)
  $rows = @(& (Join-Path $Root 'app/tools/find-runtimes.ps1') -Kind R | ConvertFrom-Json)
  $valid = @()
  foreach ($row in $rows) {
    try {
      $probe=Invoke-BiometaR $row.path '--vanilla -e "cat(as.character(getRversion()))"'
      if ($probe.code -eq 0) { $valid += [pscustomobject]@{path=$row.path;version=$probe.stdout.Trim()} }
    } catch { }
  }
  return $valid
}
function Select-BiometaR {
  param([string]$Root, [object[]]$Rows)
  if ($Rows.Count -eq 1) { return $Rows[0].path }
  $form = New-Object Windows.Forms.Form
  $form.Text = 'biometa - 选择工作站使用的 R 环境'; $form.Width=760; $form.Height=190; $form.StartPosition='CenterScreen'
  $list = New-Object Windows.Forms.ComboBox; $list.Left=20; $list.Top=20; $list.Width=700; $list.DropDownStyle='DropDownList'
  foreach($row in $Rows){ [void]$list.Items.Add("R $($row.version) - $($row.path)") }
  $use=New-Object Windows.Forms.Button; $use.Text='使用所选 R';$use.Left=20;$use.Top=70;$use.Width=160
  $browse=New-Object Windows.Forms.Button; $browse.Text='浏览 Rscript.exe';$browse.Left=200;$browse.Top=70;$browse.Width=180
  $use.Add_Click({if($list.SelectedIndex -ge 0){$form.Tag=$Rows[$list.SelectedIndex].path;$form.DialogResult='OK'}}.GetNewClosure())
  $browse.Add_Click({$picker=New-Object Windows.Forms.OpenFileDialog;$picker.Filter='Rscript (Rscript.exe)|Rscript.exe';if($picker.ShowDialog() -eq 'OK'){$form.Tag=$picker.FileName;$form.DialogResult='OK'};$picker.Dispose()}.GetNewClosure())
  $form.Controls.AddRange(@($list,$use,$browse));[void]$form.ShowDialog();$result=$form.Tag;$form.Dispose();return $result
}
function Get-BundledInstaller {
  param([string]$Root)
  $folder=Join-Path $Root 'installers';$meta=Get-Content -LiteralPath (Join-Path $folder 'r-installer.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $target=Join-Path $folder $meta.file
  if(-not(Test-Path -LiteralPath $target)){
    $cache=Join-Path $Root 'app/results/downloads';New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $target=Join-Path $cache $meta.file
    if($meta.parts){
      $stream=[IO.File]::Create($target)
      try{foreach($part in $meta.parts){$partStream=[IO.File]::OpenRead((Join-Path $folder $part));try{$partStream.CopyTo($stream)}finally{$partStream.Dispose()}}}finally{$stream.Dispose()}
    }else{Invoke-WebRequest -UseBasicParsing -Uri $meta.source -OutFile $target}
  }
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine $meta.sha256){throw 'R installer checksum mismatch.'}
  return $target
}
function Install-BiometaR {
  param([string]$Root)
  $choice=[Windows.Forms.MessageBox]::Show('未找到 R 环境。是否使用内置安装包？
是：运行已校验的内置 R 安装程序。
否：从国内 CRAN 镜像下载最新 R。
取消：浏览选择已有 Rscript.exe。','biometa - R setup','YesNoCancel','Question')
  if($choice -eq 'Cancel'){return}
  if($choice -eq 'Yes'){$installer=Get-BundledInstaller $Root}else{
    $base='https://mirrors.tuna.tsinghua.edu.cn/CRAN/bin/windows/base/'
    $html=(Invoke-WebRequest -UseBasicParsing -Uri $base).Content
    $match=[regex]::Match($html,'R-[0-9]+\.[0-9]+\.[0-9]+-win\.exe')
    if(-not $match.Success){throw 'Cannot find the current R release on the mirror. Use bundled installer or browse R.'}
    $cache=Join-Path $Root 'app/results/downloads';New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $installer=Join-Path $cache $match.Value
    Invoke-WebRequest -UseBasicParsing -Uri ($base+$match.Value) -OutFile $installer
    $version=$match.Value -replace '^R-|\-win.exe$',''
    $checks=(Invoke-WebRequest -UseBasicParsing -Uri ($base+'md5sum.R-'+$version+'.txt')).Content
    if($checks -notmatch (Get-FileHash -LiteralPath $installer -Algorithm MD5).Hash){throw 'Downloaded R installer checksum mismatch.'}
    $ok=[Windows.Forms.MessageBox]::Show("Downloaded $($match.Value). Run its installation wizard?",'biometa','YesNo','Question');if($ok -ne 'Yes'){return}
  }
  $process=Start-Process -FilePath $installer -PassThru -Wait
  if($process.ExitCode -notin @(0,3010)){throw 'R installation did not finish successfully.'}
}
function Invoke-BiometaR {
  param([string]$Path,[string]$Arguments,[int]$Timeout=15000)
  $info=New-Object Diagnostics.ProcessStartInfo
  $info.FileName=$Path;$info.Arguments=$Arguments;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $info.EnvironmentVariables.Remove('R_HOME')
  # R on Windows cannot read Chinese UTF-8 source under an inherited C.UTF-8 locale.
  $info.EnvironmentVariables['LC_ALL']='English_United States.utf8'
  $process=New-Object Diagnostics.Process;$process.StartInfo=$info;[void]$process.Start()
  $stdout=$process.StandardOutput.ReadToEndAsync()
  $stderr=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit($Timeout)){$process.Kill();$process.Dispose();throw 'R environment check timed out.'}
  $result=[pscustomobject]@{code=$process.ExitCode;stdout=$stdout.GetAwaiter().GetResult();stderr=$stderr.GetAwaiter().GetResult()}
  $process.Dispose();return $result
}
