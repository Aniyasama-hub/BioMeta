param([ValidateSet('folder','R','Python','RStudio')][string]$Kind)
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
if ($Kind -eq 'folder') {
 $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
 $dialog.Description = '选择项目工作文件夹'
} else {
 $dialog = New-Object System.Windows.Forms.OpenFileDialog
 $dialog.Title = "选择 $Kind 可执行文件"
 $dialog.Filter = '程序 (*.exe)|*.exe'
}
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
 if ($Kind -eq 'folder') { [Console]::Write($dialog.SelectedPath) } else { [Console]::Write($dialog.FileName) }
}
$dialog.Dispose()
