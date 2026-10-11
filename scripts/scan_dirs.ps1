# scan_dirs.ps1 — 目录占用扫描（只读 L0，不修改任何内容）
# 用法: powershell -ExecutionPolicy Bypass -File scan_dirs.ps1 [-Drive D] [-MinMB 5] [-BigMB 100]
# 输出: 一级目录大小、二级目录大小(>MinMB)、大文件(>BigMB)
param(
  [string]$Drive = "D",
  [int]$MinMB = 5,
  [int]$BigMB = 100
)
$ErrorActionPreference = "SilentlyContinue"
$root = "$Drive`:\"
function MB($b) { if ($null -eq $b) { 0 } else { [math]::Round($b/1MB) } }
function DirSize($p) {
  try { $s = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; if ($null -eq $s) { 0 } else { $s } } catch { 0 }
}

Write-Output "===== $root 一级目录 ====="
Get-ChildItem $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $s = DirSize $_.FullName
  Write-Output ("{0}`t{1} MB`t{2:yyyy-MM-dd}" -f $_.Name, (MB $s), $_.LastWriteTime)
}

Write-Output "`n===== 二级目录 (>$MinMB MB) ====="
Get-ChildItem $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $top = $_
  Write-Output ("--- {0} ---" -f $top.Name)
  Get-ChildItem $top.FullName -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $s = DirSize $_.FullName
    if ($s -gt ($MinMB * 1MB)) { Write-Output ("  {0}`t{1} MB" -f $_.Name, (MB $s)) }
  }
}

Write-Output "`n===== 大文件 (>$BigMB MB) ====="
Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt ($BigMB * 1MB) } |
  Sort-Object Length -Descending | Select-Object -First 30 |
  ForEach-Object { Write-Output ("{0} MB`t{1}`t({2:yyyy-MM-dd})" -f (MB $_.Length), $_.FullName, $_.LastWriteTime) }

Write-Output "`n扫描完成(未做任何修改)"
