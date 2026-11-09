param([string]$Rscript='', [ValidateRange(1024,65515)][int]$Port=7878, [switch]$NoBrowser, [int]$TestSeconds=0)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'environment.ps1')
$settingsFile=Join-Path $root 'app/results/toolbox/settings.json'
$runtimeFile=Join-Path $root 'app/results/toolbox/launcher-runtime.json'
$key=[BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace('-','')
$new=$false;$mutex=New-Object Threading.Mutex($true,"Local\biometa-$key",[ref]$new)
if(-not $new){if(-not $NoBrowser -and (Test-Path $runtimeFile)){$old=Get-Content $runtimeFile -Raw | ConvertFrom-Json;Start-Process $old.url};$mutex.Dispose();exit}
$script:server=$null;$script:notify=$null;$script:opened=$false;$script:closing=$false
function Stop-OwnedServer {
  if($script:server -and -not $script:server.HasExited){ & taskkill.exe /PID $script:server.Id /T /F 2>$null | Out-Null }
}
function Confirm-Stop {
  $jobs=Join-Path $root 'app/results/toolbox/jobs'
  $active=@(Get-ChildItem -LiteralPath $jobs -Filter status.json -Recurse -ErrorAction SilentlyContinue | Where-Object {
    try{(Get-Content $_.FullName -Raw | ConvertFrom-Json).status -in @('queued','running')}catch{$false}
  })
  if($active.Count){return [Windows.Forms.MessageBox]::Show('Analysis is running. This will stop the tasks. Continue?','biometa','YesNo','Warning') -eq 'Yes'}
  return $true
}
function Start-OwnedServer {
  Stop-OwnedServer
  $chosen=0
  for($candidate=$Port;$candidate -lt $Port+20;$candidate++){
    $listener=$null
    try{$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$candidate);$listener.Start();$chosen=$candidate;break}catch{}finally{if($listener){$listener.Stop()}}
  }
  if(-not $chosen){throw 'No free local port.'}
  $script:url="http://127.0.0.1:$chosen";$script:opened=$false;$script:started=Get-Date
  $logs=Join-Path $root 'logs';New-Item -ItemType Directory -Path $logs -Force | Out-Null
  $stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff';$stdout=Join-Path $logs "service-$stamp.log";$stderr=Join-Path $logs "service-$stamp.err.log"
  $env:LC_ALL='English_United States.utf8'
  Remove-Item Env:R_HOME -ErrorAction SilentlyContinue
  $app=Join-Path $root 'app';$entry=Join-Path $app 'start.R';$startup=Join-Path $logs "startup-$stamp.log"
  $arguments=@('--vanilla',('"'+$entry+'"'),('"'+$app+'"'),[string]$chosen,'FALSE',('"'+$startup+'"'))
  $script:server=Start-Process -FilePath $Rscript -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  @{pid=$script:server.Id;launcher_pid=$PID;url=$script:url;root=$root} | ConvertTo-Json | Set-Content $runtimeFile -Encoding UTF8
}
function Update-TrayLanguage {
  try{$language=(Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json).language}catch{$language='zh-CN'}
  $labels=switch($language){
    'en' {@('Open workstation','Refresh workstation','Exit')}
    'fr' {@('Ouvrir le poste','Redémarrer le poste','Quitter')}
    'zh-TW' {@('開啟工作站','重新啟動工作站','結束')}
    default {@('打开工作站','刷新整个工作站','退出')}
  }
  $script:openItem.Text=$labels[0];$script:refreshItem.Text=$labels[1];$script:exitItem.Text=$labels[2]
}
try {
  $settings=if(Test-Path $settingsFile){Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json}else{[pscustomobject]@{}}
  if(-not $Rscript -and $settings.rscript -and (Test-Path -LiteralPath $settings.rscript)){$Rscript=$settings.rscript}
  if(-not $Rscript){
    $rows=@(Find-BiometaR $root)
    if(-not $rows.Count){Install-BiometaR $root;$rows=@(Find-BiometaR $root)}
    $Rscript=Select-BiometaR $root $rows
  }
  if(-not $Rscript){exit}
  if((Split-Path -Leaf $Rscript) -ine 'Rscript.exe'){throw 'Please select Rscript.exe.'}
  $probe=Invoke-BiometaR $Rscript '--vanilla -e "cat(as.character(getRversion()))"'
  if($probe.code -ne 0){throw ('The selected R cannot run: '+$probe.stderr)}
  $settings | Add-Member -NotePropertyName rscript -NotePropertyValue $Rscript -Force
  New-Item -ItemType Directory -Path (Split-Path $settingsFile -Parent) -Force | Out-Null
  $settings | ConvertTo-Json -Depth 30 | Set-Content $settingsFile -Encoding UTF8
  # Generate this machine's shortcut; never distribute a .lnk containing another machine's paths.
  $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut((Join-Path $root 'biometa.lnk'))
  $link.TargetPath=Join-Path $env:WINDIR 'System32/wscript.exe';$link.Arguments='"'+(Join-Path $PSScriptRoot 'start.vbs')+'"';$link.WorkingDirectory=$root;$link.IconLocation=(Join-Path $PSScriptRoot 'biometa.ico')+',0';$link.Save()
  $check=Invoke-BiometaR $Rscript ('--vanilla "'+(Join-Path $root 'app/tools/bootstrap.R')+'" --check') 30000
  if($check.code -ne 0){
    if($check.code -ne 2 -or $TestSeconds -gt 0){throw ('R dependency check failed: '+$check.stdout+$check.stderr)}
    if([Windows.Forms.MessageBox]::Show('Required R packages are missing. Install them now? This requires Internet access.','biometa','YesNo','Question') -ne 'Yes'){throw 'Missing R packages. See INSTALL.md.'}
    $form=New-Object Windows.Forms.Form;$form.Text='biometa - Preparing R packages';$form.Width=720;$form.Height=480
    $text=New-Object Windows.Forms.TextBox;$text.Multiline=$true;$text.ReadOnly=$true;$text.Dock='Fill';$text.ScrollBars='Vertical';$form.Controls.Add($text);$form.Show()
    $log=Join-Path (Split-Path $settingsFile -Parent) 'first-use-packages.log';$err=$log+'.err'
    $env:LC_ALL='English_United States.utf8'
    Remove-Item Env:R_HOME -ErrorAction SilentlyContinue
    $install=Start-Process $Rscript -ArgumentList @('--vanilla',('"'+(Join-Path $root 'app/tools/bootstrap.R')+'"'),'--install') -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
    while(-not $install.HasExited){if(Test-Path $log){$text.Text=(Get-Content $log -Tail 60) -join [Environment]::NewLine};[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 200}
    $form.Dispose();if($install.ExitCode -ne 0){throw "Package installation failed. See $log and $err"}
  }
  $script:notify=New-Object Windows.Forms.NotifyIcon;$script:notify.Icon=New-Object Drawing.Icon((Join-Path $PSScriptRoot 'biometa.ico'));$script:notify.Text='biometa (Beta)';$script:notify.Visible=$true
  $menu=New-Object Windows.Forms.ContextMenuStrip
  $open=$menu.Items.Add('Open workstation');$open.Add_Click({Start-Process $script:url})
  $refresh=$menu.Items.Add('Refresh workstation');$refresh.Add_Click({if(Confirm-Stop){try{Start-OwnedServer}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'biometa')}}})
  $exit=$menu.Items.Add('Exit');$exit.Add_Click({if(Confirm-Stop){$script:closing=$true;[Windows.Forms.Application]::ExitThread()}})
  $script:openItem=$open;$script:refreshItem=$refresh;$script:exitItem=$exit;Update-TrayLanguage
  $script:notify.ContextMenuStrip=$menu;$script:notify.Add_DoubleClick({Start-Process $script:url})
  Start-OwnedServer
  $timer=New-Object Windows.Forms.Timer;$timer.Interval=1000
  $timer.Add_Tick({
    Update-TrayLanguage
    if($script:server.HasExited){
      $timer.Stop()
      if($script:server.ExitCode -ne 0){[void][Windows.Forms.MessageBox]::Show('The R service stopped. Check the local logs folder.','biometa')}
      [Windows.Forms.Application]::ExitThread();return
    }
    if(-not $script:opened){try{$request=[Net.WebRequest]::Create($script:url);$request.Timeout=500;$response=$request.GetResponse();$response.Close();$script:opened=$true;if(-not $NoBrowser){Start-Process $script:url}}catch{}}
    if($TestSeconds -gt 0 -and ((Get-Date)-$script:started).TotalSeconds -ge $TestSeconds){[Windows.Forms.Application]::ExitThread()}
  });$timer.Start();[Windows.Forms.Application]::Run();$timer.Dispose()
}catch{if($TestSeconds -gt 0){Write-Error $_ -ErrorAction Continue}else{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'biometa startup error','OK','Error')};exit 1}
finally{Stop-OwnedServer;if($script:notify){$script:notify.Visible=$false;$script:notify.Dispose()};if(Test-Path $runtimeFile){Remove-Item -LiteralPath $runtimeFile -Force};$mutex.ReleaseMutex();$mutex.Dispose()}
