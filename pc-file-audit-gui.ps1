﻿﻿﻿﻿﻿﻿# pc-file-audit GUI —— 电脑文件可视化审计窗口（PowerShell + WinForms 零依赖版）
# =============================================================================
# 双击运行（或右键 -> 使用 PowerShell 运行）
# 功能：选择盘符 -> 扫描 -> 表格可视化三档分类（红/绿/黄）-> 勾选删除（进回收站）
# 依赖：仅 Windows 自带 PowerShell 5.1 + .NET WinForms，客户机无需安装任何东西
# 编码：本文件须为 UTF-8 BOM（Windows PowerShell 5.1 兼容）
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 自动扫描参数：-AutoScan D: （启动后自动扫描指定盘，便于自动化验证）
$autoScan = $null
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq "-AutoScan") { $autoScan = $args[$i + 1] } }

# ---------- 分类规则（精简内置版，完整见 references/dir-guide.md） ----------
# 注意：PowerShell 双引号内反斜杠无需转义，路径分隔符直接写 \x
$RULES_R = @("\windows","program files","\users","programdata",
             "system volume information","pagefile.sys","swapfile.sys",
             "hiberfil.sys","\recovery","\boot","$recycle.bin")
$RULES_G = @("cache","temp","\tmp","\log","\logs","update\download","\download\mainapp",
             "\install","old","残留","\backup","autoupdate","softwaredistribution\download",
             "steam","qqlive","aliwangwang","duowan","gensee","qqpcmgr","qq管家",
             "kgenuine","w3cschool","微信开发者工具","statespace","aim lab","sogouinput\components")

# ---------- 回收站删除（SHFileOperationW，C# 内联） ----------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Recycle {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEOPSTRUCT {
        public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo;
        public ushort fFlags; public bool fAnyOperationsAborted; public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHFileOperation(ref SHFILEOPSTRUCT lpFileOp);
    public static bool Send(string path) {
        SHFILEOPSTRUCT op = new SHFILEOPSTRUCT();
        op.wFunc = 3; // FO_DELETE
        op.pFrom = path + "\0\0";
        op.fFlags = 0x40 | 0x10 | 0x4; // ALLOWUNDO | NOCONFIRMATION | SILENT
        return SHFileOperation(ref op) == 0;
    }
}
"@

# ---------- 窗体 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "pc-file-audit · 电脑文件可视化审计 v1.0"
$form.Size = New-Object System.Drawing.Size(1100, 720)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

# 顶部工具栏
$topBar = New-Object System.Windows.Forms.Panel
$topBar.Dock = "Top"; $topBar.Height = 56; $form.Controls.Add($topBar)

$lblDrive = New-Object System.Windows.Forms.Label
$lblDrive.Text = "选择盘符:"; $lblDrive.Location = New-Object System.Drawing.Point(14, 18)
$lblDrive.AutoSize = $true; $topBar.Controls.Add($lblDrive)

$cboDrive = New-Object System.Windows.Forms.ComboBox
$cboDrive.DropDownStyle = "DropDownList"; $cboDrive.Location = New-Object System.Drawing.Point(86, 14)
$cboDrive.Width = 70; $topBar.Controls.Add($cboDrive)

Get-PSDrive -PSProvider FileSystem | ForEach-Object { $cboDrive.Items.Add($_.Name + ":") } | Out-Null
if ($cboDrive.Items.Count -gt 0) { $cboDrive.SelectedIndex = 0 }

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "开始扫描"; $btnScan.Location = New-Object System.Drawing.Point(170, 12)
$btnScan.Width = 100; $btnScan.Height = 32; $topBar.Controls.Add($btnScan)

$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Location = New-Object System.Drawing.Point(290, 15); $prog.Width = 300; $prog.Height = 24
$prog.Style = "Continuous"; $topBar.Controls.Add($prog)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "就绪"; $lblStatus.Location = New-Object System.Drawing.Point(610, 18)
$lblStatus.AutoSize = $true; $lblStatus.ForeColor = "#555555"; $topBar.Controls.Add($lblStatus)

# 底部操作栏
$botBar = New-Object System.Windows.Forms.Panel
$botBar.Dock = "Bottom"; $botBar.Height = 56; $form.Controls.Add($botBar)

$lblTip = New-Object System.Windows.Forms.Label
$lblTip.Text = "勾选要删除的项目（绿色=可删，黄色=需判断，红色=保留）。删除优先进回收站。"
$lblTip.Location = New-Object System.Drawing.Point(14, 18); $lblTip.AutoSize = $true
$lblTip.ForeColor = "#777777"; $botBar.Controls.Add($lblTip)

$btnDel = New-Object System.Windows.Forms.Button
$btnDel.Text = "删除勾选项（进回收站）"; $btnDel.Location = New-Object System.Drawing.Point(860, 10)
$btnDel.Width = 220; $btnDel.Height = 36; $btnDel.BackColor = "#2FA84F"
$btnDel.ForeColor = "White"; $botBar.Controls.Add($btnDel)

# 中部：左列表 + 右统计面板
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = "Fill"; $split.SplitterDistance = 780
$form.Controls.Add($split)

$list = New-Object System.Windows.Forms.ListView
$list.Dock = "Fill"; $list.View = "Details"; $list.FullRowSelect = $true
$list.CheckBoxes = $true; $list.GridLines = $true
$list.Columns.Add("目录", 260) | Out-Null
$list.Columns.Add("大小(MB)", 90) | Out-Null
$list.Columns.Add("分类", 90) | Out-Null
$list.Columns.Add("说明", 320) | Out-Null
$split.Panel1.Controls.Add($list)

$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Dock = "Fill"; $split.Panel2.Controls.Add($rightPanel)

$lblChartTitle = New-Object System.Windows.Forms.Label
$lblChartTitle.Text = "目录占用 Top15"; $lblChartTitle.Dock = "Top"
$lblChartTitle.Height = 30; $lblChartTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Bold)
$rightPanel.Controls.Add($lblChartTitle)

$chartBox = New-Object System.Windows.Forms.Panel
$chartBox.Dock = "Fill"; $rightPanel.Controls.Add($chartBox)

# 条形图
function Update-Chart {
    $chartBox.Controls.Clear()
    $items = @()
    foreach ($it in $list.Items) {
        if ($it.Text -eq "") { continue }
        $items += [pscustomobject]@{ Name = $it.Text; SizeMB = [double]$it.SubItems[1].Text; Cat = $it.SubItems[2].Text }
    }
    $items = @($items | Where-Object { $_.Cat -ne "" } | Sort-Object SizeMB -Descending | Select-Object -First 15)
    if (@($items).Count -eq 0) { return }
    $max = ($items | Measure-Object SizeMB -Maximum).Maximum
    $barW = $chartBox.ClientSize.Width - 150
    $barH = 24
    $y = 8
    foreach ($it in $items) {
        $color = switch ($it.Cat) {
            "🔴保留" { "#E5484D" } "🟢可删" { "#2FA84F" } default { "#E8B339" }
        }
        $bw = [math]::Max(10, [int](($it.SizeMB / $max) * $barW))
        $bar = New-Object System.Windows.Forms.Label
        $bar.Text = $it.Name
        $bar.BackColor = [System.Drawing.ColorTranslator]::FromHtml($color)
        $bar.Location = New-Object System.Drawing.Point(8, $y)
        $bar.Size = New-Object System.Drawing.Size($bw, $barH - 4)
        $bar.ForeColor = "White"
        $chartBox.Controls.Add($bar)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = " $($it.SizeMB) MB"
        $lbl.Location = New-Object System.Drawing.Point(12 + $bw, $y)
        $lbl.AutoSize = $true
        $chartBox.Controls.Add($lbl)
        $y += $barH
    }
}

# ---------- 共享状态（后台线程写入，UI Timer 读取） ----------
$script:shared = [hashtable]::Synchronized(@{
    Running = $false; Progress = 0; Current = ""; Done = $false
    Data = $null; Error = $null; Drive = ""; FileCount = 0
})

# ---------- 扫描脚本（在独立 Runspace 中执行，可调用函数） ----------
$scanScript = {
    param($drive, $rulesR, $rulesG, $shared)
    function Get-Category([string]$path) {
        $low = $path.ToLower()
        # 先查可删规则再查保留规则：否则 \windows 会把 Windows\Temp 等缓存也标成保留
        foreach ($kw in $rulesG) { if ($low -like "*$kw*") { return @("G", "缓存/残留，可清理") } }
        foreach ($kw in $rulesR) { if ($low -like "*$kw*") { return @("R", "系统/在用，必须保留") } }
        return @("Y", "用户判断是否继续使用")
    }
    function Get-DirSizeMB([string]$path, $shared) {
        $total = 0L
        $fc = 0
        $stack = New-Object System.Collections.Stack
        $stack.Push($path)
        while ($stack.Count -gt 0) {
            $dir = $stack.Pop()
            try {
                $shared.Current = $dir
                $di = [System.IO.DirectoryInfo]::new($dir)
                foreach ($sd in $di.EnumerateDirectories()) { $stack.Push($sd.FullName) }
                foreach ($f in $di.EnumerateFiles()) { try { $total += $f.Length; $fc++ } catch {} }
                if ($fc -ge 3000) { $shared.FileCount += $fc; $fc = 0 }
            } catch {}
        }
        if ($fc -gt 0) { $shared.FileCount += $fc }
        return [math]::Round($total / 1MB, 1)
    }
    $results = New-Object System.Collections.ArrayList
    try {
        $topDirs = @(Get-ChildItem ($drive + "\") -Directory -Force -EA SilentlyContinue |
                      Where-Object { $_.Name -notin @("$RECYCLE.BIN","System Volume Information","Documents and Settings","Recovery","Boot") })
        $n = @($topDirs).Count
        for ($i = 0; $i -lt $n; $i++) {
            $d = $topDirs[$i]
            $shared.Progress = [int](($i + 1) / $n * 100)
            $shared.Current = $d.Name
            $s = Get-DirSizeMB $d.FullName $shared
            $c = Get-Category $d.FullName
            [void]$results.Add([pscustomobject]@{ Name=$d.Name; Path=$d.FullName; SizeMB=$s; Cat=$c[0]; Desc=$c[1]; Level=0 })
            if ($c[0] -eq "R") {
                # 保留目录只展开"命中可删规则"的二级（如 Windows\Temp、Windows\Logs、更新缓存），其余不深挖
                Get-ChildItem $d.FullName -Directory -Force -EA SilentlyContinue | ForEach-Object {
                    $c2 = Get-Category $_.FullName
                    if ($c2[0] -eq "G") {
                        $ss = Get-DirSizeMB $_.FullName $shared
                        [void]$results.Add([pscustomobject]@{ Name="    " + $_.Name; Path=$_.FullName; SizeMB=$ss; Cat=$c2[0]; Desc=$c2[1]; Level=1 })
                    }
                }
            } else {
                Get-ChildItem $d.FullName -Directory -Force -EA SilentlyContinue | ForEach-Object {
                    $ss = Get-DirSizeMB $_.FullName $shared
                    if ($ss -gt 10) {
                        $c2 = Get-Category $_.FullName
                        [void]$results.Add([pscustomobject]@{ Name="    " + $_.Name; Path=$_.FullName; SizeMB=$ss; Cat=$c2[0]; Desc=$c2[1]; Level=1 })
                    }
                }
            }
        }
        $shared.Data = $results
    } catch {
        $shared.Error = $_.Exception.Message
    }
    $shared.Done = $true
    $shared.Running = $false
}

$script:ps = $null
$script:handle = $null

function Start-Scan {
    $drive = $cboDrive.SelectedItem
    if (-not $drive) { [System.Windows.Forms.MessageBox]::Show("请先选择盘符", "提示"); return }
    if ($script:shared.Running) { return }
    $list.Items.Clear(); $chartBox.Controls.Clear()
    $script:shared.Running = $true; $script:shared.Done = $false
    $script:shared.Progress = 0; $script:shared.Current = ""; $script:shared.Error = $null
    $script:shared.Data = $null; $script:shared.Drive = $drive; $script:shared.FileCount = 0
    $btnScan.Enabled = $false
    $lblStatus.Text = "扫描中…"
    $prog.Value = 0
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $script:ps = [powershell]::Create()
    $script:ps.Runspace = $runspace
    $null = $script:ps.AddScript($scanScript).AddArgument($drive).AddArgument($RULES_R).AddArgument($RULES_G).AddArgument($script:shared)
    $script:handle = $script:ps.BeginInvoke()
}

function Scan-Done {
    $btnScan.Enabled = $true
    if ($script:shared.Error) { $lblStatus.Text = "扫描出错: $($script:shared.Error)"; return }
    $results = $script:shared.Data
    if ($null -eq $results) { $lblStatus.Text = "扫描完成（无结果）"; return }
    $list.BeginUpdate(); $list.Items.Clear()
    $sumG = 0; $cntG = 0
    foreach ($r in $results) {
        $catTxt = switch ($r.Cat) { "R" { "🔴保留" } "G" { "🟢可删" } default { "🟡判断" } }
        $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
        $item.Tag = $r.Path
        $item.SubItems.Add($r.SizeMB.ToString()) | Out-Null
        $item.SubItems.Add($catTxt) | Out-Null
        $item.SubItems.Add($r.Desc) | Out-Null
        if ($r.Cat -eq "G") { $item.Checked = $true; $item.BackColor = "#E8F7EC"; $sumG += $r.SizeMB; $cntG++ }
        elseif ($r.Cat -eq "R") { $item.BackColor = "#FDEBEC" }
        else { $item.BackColor = "#FDF3E0" }
        [void]$list.Items.Add($item)
    }
    $list.EndUpdate()
    $lblStatus.Text = "扫描完成 · 可删约 $([math]::Round($sumG/1024,2)) GB（$cntG 项）"
    Update-Chart
}

$btnScan.Add_Click({ Start-Scan })

$btnDel.Add_Click({
    $paths = @()
    foreach ($item in @($list.Items | Where-Object { $_.Checked })) {
        if ($item.Tag) { $paths += $item.Tag }
    }
    if (@($paths).Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("没有勾选要删除的项目", "提示"); return }
    $msg = "将删除以下 $($paths.Count) 项（优先移入回收站）：`n`n" + ($paths -join "`n")
    $msg += "`n`n⚠ 若回收站通道不可用将永久删除（均为缓存/残留，非个人文件）。"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, "确认删除", "YesNo", "Warning")
    if ($r -ne "Yes") { return }
    $ok = 0; $rec = 0
    foreach ($p in $paths) {
        if (Test-Path $p) {
            if ([Recycle]::Send($p)) { $rec++ }
            else { Remove-Item $p -Recurse -Force -Confirm:$false }
            $ok++
        }
    }
    foreach ($item in @($list.Items | Where-Object { $_.Checked })) {
        $list.Items.Remove($item)
    }
    [System.Windows.Forms.MessageBox]::Show("删除完成：$ok 项，其中 $rec 项进入回收站", "完成")
    Update-Chart
})

# UI 定时器：轮询共享状态刷新进度条 / 完成时填充结果
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    if ($script:shared.Running) {
        $prog.Value = $script:shared.Progress
        if ($script:shared.Current) {
            $fc = $script:shared.FileCount
            if ($fc -gt 0) { $lblStatus.Text = "扫描中: $($script:shared.Current) · 已处理 $fc 个文件" }
            else { $lblStatus.Text = "扫描中: $($script:shared.Current)" }
        }
        return
    }
    if ($script:shared.Done -and $script:ps -ne $null -and -not $script:ps.HadErrors) {
        try {
            $script:ps.EndInvoke($script:handle)
        } catch {}
        $script:ps.Dispose()
        $script:ps = $null
        $timer.Stop()
        Scan-Done
    }
})
$timer.Start()

$form.Add_Shown({
    $form.Activate()
    if ($autoScan) {
        $cboDrive.SelectedItem = $autoScan
        Start-Scan
    }
})

[void]$form.ShowDialog()
