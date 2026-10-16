# qingpanxia GUI v1.4 —— 电脑文件可视化审计窗口（PowerShell + WinForms 零依赖版）
# =============================================================================
# 双击运行（或右键 -> 使用 PowerShell 运行）
# v1.4 现代化改版：统一设计语言（圆角卡片/渐变/胶囊chips/柔和配色/清晰层级）
# 功能不变：选盘扫描 -> 三档分类表格 -> 搜索/chips筛选 -> 勾选删除（进回收站）
#           删除自动写变更历史收据；规则可导出/导入 JSON；自绘渐变条形图
# 依赖：仅 Windows 自带 PowerShell 5.1 + .NET WinForms，零安装
# 编码：本文件须为 UTF-8 BOM（Windows PowerShell 5.1 兼容）
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 自动扫描参数：-AutoScan D:
$autoScan = $null
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq "-AutoScan") { $autoScan = $args[$i + 1] } }

# ---------- 分类规则（Pattern / Cat / Desc / Risk） ----------
# Cat: R=必须保留 G=明确可删 Y=用户判断；Risk: L1安全清理 L2需确认 L3绝不能动
# 匹配顺序固定：先 G（可删）再 R（保留）
$script:RULES = @(
    @{ Pattern="\windows";                 Cat="R"; Desc="系统本体，绝不能动";             Risk="L3" },
    @{ Pattern="program files";            Cat="R"; Desc="已安装软件程序";                 Risk="L3" },
    @{ Pattern="\users";                   Cat="R"; Desc="用户数据/个人文件";              Risk="L3" },
    @{ Pattern="programdata";              Cat="R"; Desc="软件共享数据/配置";              Risk="L3" },
    @{ Pattern="system volume information";Cat="R"; Desc="系统还原信息";                   Risk="L3" },
    @{ Pattern="pagefile.sys";             Cat="R"; Desc="虚拟内存文件";                   Risk="L3" },
    @{ Pattern="swapfile.sys";             Cat="R"; Desc="系统交换文件";                   Risk="L3" },
    @{ Pattern="hiberfil.sys";             Cat="R"; Desc="休眠文件";                       Risk="L3" },
    @{ Pattern="\recovery";                Cat="R"; Desc="Windows 恢复环境";               Risk="L3" },
    @{ Pattern="\boot";                    Cat="R"; Desc="系统启动配置";                   Risk="L3" },
    @{ Pattern='$recycle.bin';             Cat="R"; Desc="回收站";                         Risk="L3" },
    @{ Pattern="cache";                    Cat="G"; Desc="缓存，可清理";                   Risk="L1" },
    @{ Pattern="temp";                     Cat="G"; Desc="临时文件，可清理";               Risk="L1" },
    @{ Pattern="\tmp";                     Cat="G"; Desc="临时文件，可清理";               Risk="L1" },
    @{ Pattern="\log";                     Cat="G"; Desc="日志，可清理";                   Risk="L1" },
    @{ Pattern="\logs";                    Cat="G"; Desc="日志，可清理";                   Risk="L1" },
    @{ Pattern="update\download";          Cat="G"; Desc="更新下载缓存，可清理";           Risk="L1" },
    @{ Pattern="\download\mainapp";        Cat="G"; Desc="下载缓存，可清理";               Risk="L1" },
    @{ Pattern="softwaredistribution\download"; Cat="G"; Desc="Windows 更新缓存";          Risk="L1" },
    @{ Pattern="autoupdate";               Cat="G"; Desc="自动更新缓存，可清理";           Risk="L1" },
    @{ Pattern="\install";                 Cat="G"; Desc="安装程序残留缓存，可清理";       Risk="L2" },
    @{ Pattern="old";                      Cat="G"; Desc="旧版本/旧文件残留，可清理";      Risk="L2" },
    @{ Pattern="残留";                     Cat="G"; Desc="卸载残留，可清理";               Risk="L2" },
    @{ Pattern="\backup";                  Cat="G"; Desc="备份缓存，可清理";               Risk="L2" },
    @{ Pattern="qqpcmgr";                  Cat="G"; Desc="QQ 管家残留，可清理";            Risk="L2" },
    @{ Pattern="qq管家";                   Cat="G"; Desc="QQ 管家残留，可清理";            Risk="L2" },
    @{ Pattern="kgenuine";                 Cat="G"; Desc="金山残留，可清理";               Risk="L2" },
    @{ Pattern="w3cschool";                Cat="G"; Desc="W3Cschool 残留，可清理";         Risk="L2" },
    @{ Pattern="statespace";               Cat="G"; Desc="Aim Lab 残留，可清理";           Risk="L2" },
    @{ Pattern="aim lab";                  Cat="G"; Desc="Aim Lab 残留，可清理";           Risk="L2" },
    @{ Pattern="sogouinput\components";    Cat="G"; Desc="搜狗输入法旧组件，可清理";       Risk="L2" },
    @{ Pattern="steam";                    Cat="G"; Desc="Steam 平台残留（用户是否在用？）"; Risk="L2" },
    @{ Pattern="qqlive";                   Cat="G"; Desc="腾讯视频残留（用户是否在用？）";   Risk="L2" },
    @{ Pattern="aliwangwang";              Cat="G"; Desc="阿里旺旺残留（用户是否在用？）";   Risk="L2" },
    @{ Pattern="duowan";                   Cat="G"; Desc="多玩游戏盒残留（用户是否在用？）"; Risk="L2" },
    @{ Pattern="gensee";                   Cat="G"; Desc="展视会议残留（用户是否在用？）";   Risk="L2" },
    @{ Pattern="微信开发者工具";            Cat="G"; Desc="微信开发者工具残留（用户是否在用？）"; Risk="L2" }
)

# ---------- 变更历史收据 ----------
$script:historyFile = Join-Path $PSScriptRoot "ChangeHistory.txt"
function Add-HistoryBatch([string]$header, [string[]]$lines) {
    try {
        $encBom = New-Object System.Text.UTF8Encoding($true)
        $encNo  = New-Object System.Text.UTF8Encoding($false)
        if (-not (Test-Path $script:historyFile)) {
            [System.IO.File]::WriteAllText($script:historyFile, "", $encBom)
        }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("===== $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) $header =====")
        foreach ($l in $lines) { [void]$sb.AppendLine("    $l") }
        [System.IO.File]::AppendAllText($script:historyFile, $sb.ToString(), $encNo)
    } catch {}
}
function Show-History {
    try {
        if (Test-Path $script:historyFile) { Start-Process notepad $script:historyFile }
        else { [System.Windows.Forms.MessageBox]::Show("还没有删除记录。勾选项目删除后会自动写入。", "变更历史") }
    } catch { [System.Windows.Forms.MessageBox]::Show("打开记录失败: $($_.Exception.Message)", "提示") }
}

# ---------- 配置导出 / 导入 ----------
function Export-Config {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.FileName = "qingpanxia-config.json"; $dlg.Filter = "JSON 配置文件 (*.json)|*.json"
    if ($dlg.ShowDialog() -ne "OK") { return }
    try {
        $cfg = [pscustomobject]@{ Version = 2; Updated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Rules = $script:RULES }
        $json = $cfg | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($dlg.FileName, $json, (New-Object System.Text.UTF8Encoding($true)))
        [System.Windows.Forms.MessageBox]::Show("已导出 $($script:RULES.Count) 条规则到：`n$($dlg.FileName)", "导出配置")
    } catch { [System.Windows.Forms.MessageBox]::Show("导出失败: $($_.Exception.Message)", "提示") }
}
function Import-Config {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "JSON 配置文件 (*.json)|*.json"
    if ($dlg.ShowDialog() -ne "OK") { return }
    try {
        $cfg = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $cfg.Rules -or @($cfg.Rules).Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("配置文件格式不正确（缺少 Rules）", "提示"); return
        }
        $new = @()
        foreach ($r in @($cfg.Rules)) {
            if ($r.Pattern -and $r.Cat) {
                $new += @{ Pattern = [string]$r.Pattern; Cat = [string]$r.Cat; Desc = [string]$r.Desc; Risk = [string]$r.Risk }
            }
        }
        if (@($new).Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("配置中没有有效规则", "提示"); return }
        $script:RULES = $new
        [System.Windows.Forms.MessageBox]::Show("已导入 $(@($new).Count) 条规则", "导入配置")
        Refresh-RulePage
    } catch { [System.Windows.Forms.MessageBox]::Show("导入失败: $($_.Exception.Message)", "提示") }
}

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
        op.wFunc = 3;
        op.pFrom = path + "\0\0";
        op.fFlags = 0x40 | 0x10 | 0x4;
        return SHFileOperation(ref op) == 0;
    }
}
"@

# ============================================================
# v1.4 设计系统：配色 / 圆角工具 / 控件工厂
# ============================================================
# —— 配色 ——
$colBg      = "#F5F6F8"   # 主区浅灰
$colSurface = "#FFFFFF"   # 卡片白
$colBorder  = "#E7EAF0"   # 极浅边框
$colSide    = "#101828"   # 深色侧栏（现代）
$colSideH   = "#1D2939"   # 侧栏选中
$colBrand   = "#14B8A6"   # 品牌青绿
$colBrandD  = "#0D9488"   # 品牌深青
$colBrandL  = "#E6F7F5"   # 品牌浅底
$colGreen   = "#16A34A"   # 可删绿
$colGreenL  = "#E9F9EF"
$colRed     = "#DC2626"   # 保留红
$colRedL    = "#FDECEC"
$colYellow  = "#D97706"   # 判断黄
$colYellowL = "#FEF4E4"
$colText    = "#1F2937"   # 主文字
$colSub     = "#64748B"   # 次要文字
$colMuted   = "#94A3B8"   # 弱文字

$radius = 10   # 卡片圆角半径

# —— 自绘圆角工具 ——
function New-RoundedPath([int]$x, [int]$y, [int]$w, [int]$h, [int]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($w -le 0 -or $h -le 0) { $p.AddRectangle((New-Object System.Drawing.Rectangle($x, $y, [math]::Max(1,$w), [math]::Max(1,$h)))); return $p }
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# 圆角卡片面板（浅边框 + 白底）
function New-Card([int]$x, [int]$y, [int]$w, [int]$h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $colSurface
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path = New-RoundedPath 0 0 ($s.ClientSize.Width - 1) ($s.ClientSize.Height - 1) $radius
        $g.DrawPath((New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($colBorder))), $path)
        $path.Dispose()
    })
    return $p
}

# 圆角按钮（主/次/危险 三态）
function New-RoundBtn([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [string]$mode = "primary") {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $colSurface
    $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5)
    $b.Tag = $mode
    $b.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $r = 9
        $path = New-RoundedPath 0 0 ($s.ClientSize.Width - 1) ($s.ClientSize.Height - 1) $r
        $mode = $s.Tag
        $hover = ($s.FlatAppearance.MouseOverBackColor -eq [System.Drawing.Color]::Transparent) -and $s.Capture
        switch ($mode) {
            "primary" {
                $c1 = [System.Drawing.ColorTranslator]::FromHtml($colBrand)
                $c2 = [System.Drawing.ColorTranslator]::FromHtml($colBrandD)
                $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($s.ClientRectangle, $c1, $c2, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
                $g.FillPath($br, $path); $br.Dispose()
                $s.ForeColor = "White"
            }
            "danger" {
                $br = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colGreen))
                $g.FillPath($br, $path); $br.Dispose()
                $s.ForeColor = "White"
            }
            default {
                $br = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colSurface))
                $g.FillPath($br, $path); $br.Dispose()
                $g.DrawPath((New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($colBorder))), $path)
                $s.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($colText)
            }
        }
        $path.Dispose()
    })
    $b.Add_MouseEnter({ param($s, $e) $s.Invalidate() })
    $b.Add_MouseLeave({ param($s, $e) $s.Invalidate() })
    return $b
}

# 胶囊标签（状态徽章/分类徽章）
function New-Capsule([string]$text, [int]$x, [int]$y, [string]$bg, [string]$fg, [int]$w = 0) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.AutoSize = $true
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Padding = New-Object System.Windows.Forms.Padding(12, 3, 12, 3)
    $l.BackColor = [System.Drawing.ColorTranslator]::FromHtml($bg)
    $l.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($fg)
    $l.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    if ($w -gt 0) { $l.Width = $w; $l.TextAlign = "MiddleCenter"; $l.AutoSize = $false }
    return $l
}

# ---------- 窗体 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "清盘侠 · 电脑文件可视化审计 v1.4"
$form.Size = New-Object System.Drawing.Size(1280, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1080, 660)
$form.StartPosition = "CenterScreen"
$form.BackColor = $colBg
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

# ---------- 左侧导航 ----------
$navBar = New-Object System.Windows.Forms.Panel
$navBar.Dock = "Left"; $navBar.Width = 172; $navBar.BackColor = $colSide
$form.Controls.Add($navBar)

# Logo 区
$logoPanel = New-Object System.Windows.Forms.Panel
$logoPanel.Dock = "Top"; $logoPanel.Height = 92; $logoPanel.BackColor = $colSide
$navBar.Controls.Add($logoPanel)
$lblMark = New-Object System.Windows.Forms.Label
$lblMark.Text = "清盘侠"; $lblMark.Dock = "Top"; $lblMark.Height = 44
$lblMark.ForeColor = "White"; $lblMark.TextAlign = "MiddleCenter"
$lblMark.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 17, [System.Drawing.FontStyle]::Bold)
$logoPanel.Controls.Add($lblMark)
$lblMarkSub = New-Object System.Windows.Forms.Label
$lblMarkSub.Text = "PC FILE AUDIT"; $lblMarkSub.Dock = "Top"; $lblMarkSub.Height = 22
$lblMarkSub.ForeColor = $colBrand; $lblMarkSub.TextAlign = "MiddleCenter"
$lblMarkSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$logoPanel.Controls.Add($lblMarkSub)
$lblDivider = New-Object System.Windows.Forms.Label
$lblDivider.Dock = "Top"; $lblDivider.Height = 1; $lblDivider.BackColor = "#243244"
$logoPanel.Controls.Add($lblDivider)

$script:navInd = @{}
$lblNavGroup = New-Object System.Windows.Forms.Label
$lblNavGroup.Text = "功能菜单"; $lblNavGroup.Location = New-Object System.Drawing.Point(20, 106)
$lblNavGroup.AutoSize = $true; $lblNavGroup.ForeColor = "#55637A"
$lblNavGroup.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
$navBar.Controls.Add($lblNavGroup)

function New-NavBtn([string]$text, [int]$top, [string]$name) {
    $ind = New-Object System.Windows.Forms.Panel
    $ind.Width = 4; $ind.Height = 30; $ind.Left = 0; $ind.Top = 6
    $ind.BackColor = $colBrand
    $script:navInd[$name] = $ind
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $colSideH
    $b.ForeColor = "#9AA6B8"; $b.BackColor = $colSide
    $b.TextAlign = "MiddleLeft"
    $b.Padding = New-Object System.Windows.Forms.Padding(20, 0, 0, 0)
    $b.Location = New-Object System.Drawing.Point(0, $top); $b.Width = 172; $b.Height = 42
    $b.Tag = $name
    $b.Controls.Add($ind)
    $navBar.Controls.Add($b)
    return $b
}
$btnNavScan  = New-NavBtn "  ⌕  扫描" 140  "scan"
$btnNavRules = New-NavBtn "  ⚙  规则" 186  "rules"
$btnNavAbout = New-NavBtn "  ⓘ  关于" 232  "about"

$navFooter = New-Object System.Windows.Forms.Label
$navFooter.Text = "v1.4 · 零依赖`n个人免费 · 商用需授权"
$navFooter.Dock = "Bottom"; $navFooter.Height = 52
$navFooter.ForeColor = "#55637A"; $navFooter.TextAlign = "MiddleCenter"
$navFooter.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
$navBar.Controls.Add($navFooter)

$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Dock = "Fill"; $form.Controls.Add($contentHost)

# ============ 页面 1：扫描 ============
$pageScan = New-Object System.Windows.Forms.Panel
$pageScan.Dock = "Fill"; $contentHost.Controls.Add($pageScan)

# —— 顶栏 ——
$topBar = New-Object System.Windows.Forms.Panel
$topBar.Dock = "Top"; $topBar.Height = 72; $topBar.BackColor = $colSurface
$pageScan.Controls.Add($topBar)
$lblTopTitle = New-Object System.Windows.Forms.Label
$lblTopTitle.Text = "全盘扫描 · 逐项决策"
$lblTopTitle.Location = New-Object System.Drawing.Point(28, 12); $lblTopTitle.AutoSize = $true
$lblTopTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 13, [System.Drawing.FontStyle]::Bold)
$lblTopTitle.ForeColor = $colText
$topBar.Controls.Add($lblTopTitle)
$lblTopSub = New-Object System.Windows.Forms.Label
$lblTopSub.Text = "只读分析 · 删除先进回收站 · 每笔留收据"
$lblTopSub.Location = New-Object System.Drawing.Point(30, 46); $lblTopSub.AutoSize = $true
$lblTopSub.ForeColor = $colSub; $lblTopSub.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
$topBar.Controls.Add($lblTopSub)

$lblDrive = New-Object System.Windows.Forms.Label
$lblDrive.Text = "盘符"; $lblDrive.Location = New-Object System.Drawing.Point(560, 26)
$lblDrive.AutoSize = $true; $lblDrive.ForeColor = $colSub; $topBar.Controls.Add($lblDrive)
$cboDrive = New-Object System.Windows.Forms.ComboBox
$cboDrive.DropDownStyle = "DropDownList"; $cboDrive.Location = New-Object System.Drawing.Point(604, 21)
$cboDrive.Width = 68; $cboDrive.FlatStyle = "Flat"; $cboDrive.Height = 28
$topBar.Controls.Add($cboDrive)
Get-PSDrive -PSProvider FileSystem | ForEach-Object { $cboDrive.Items.Add($_.Name + ":") } | Out-Null
if ($cboDrive.Items.Count -gt 0) { $cboDrive.SelectedIndex = 0 }

$btnScan = New-RoundBtn "开始扫描" 690 16 116 34 "primary"
$btnScan.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$topBar.Controls.Add($btnScan)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(850, 22); $txtSearch.Width = 250
$txtSearch.BorderStyle = "FixedSingle"; $txtSearch.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5)
$txtSearch.Add_GotFocus({ $txtSearch.ForeColor = $colText })
$topBar.Controls.Add($txtSearch)
$lblSearchHint = New-Object System.Windows.Forms.Label
$lblSearchHint.Text = "🔍  搜索目录 / 说明"
$lblSearchHint.Location = New-Object System.Drawing.Point(856, 27); $lblSearchHint.AutoSize = $true
$lblSearchHint.ForeColor = $colMuted; $lblSearchHint.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$lblSearchHint.Enabled = $false
$topBar.Controls.Add($lblSearchHint)
$txtSearch.Add_TextChanged({ $lblSearchHint.Visible = ($txtSearch.Text.Trim().Length -eq 0); $searchTimer.Stop(); $searchTimer.Start() })
$txtSearch.Add_GotFocus({ $lblSearchHint.Visible = $false })

$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Location = New-Object System.Drawing.Point(1116, 26); $prog.Width = 130; $prog.Height = 16
$prog.Style = "Continuous"; $topBar.Controls.Add($prog)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "就绪"; $lblStatus.Location = New-Object System.Drawing.Point(700, 52)
$lblStatus.AutoSize = $true; $lblStatus.ForeColor = $colSub; $lblStatus.Visible = $false
$topBar.Controls.Add($lblStatus)

# —— 统计概览卡（4 张现代化指标卡） ——
$statBar = New-Object System.Windows.Forms.Panel
$statBar.Dock = "Top"; $statBar.Height = 100; $statBar.BackColor = $colBg
$statBar.Padding = New-Object System.Windows.Forms.Padding(24, 14, 24, 0)
$pageScan.Controls.Add($statBar)

$script:statCards = @{}
function New-StatCard([string]$key, [int]$x, [string]$accent, [string]$icon, [string]$label) {
    $card = New-Card $x 14 284 78
    $strip = New-Object System.Windows.Forms.Panel
    $strip.Dock = "Left"; $strip.Width = 4; $strip.BackColor = [System.Drawing.ColorTranslator]::FromHtml($accent)
    $card.Controls.Add($strip)
    $lblI = New-Object System.Windows.Forms.Label
    $lblI.Text = $icon; $lblI.Location = New-Object System.Drawing.Point(20, 10)
    $lblI.AutoSize = $true; $lblI.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 17)
    $card.Controls.Add($lblI)
    $lblV = New-Object System.Windows.Forms.Label
    $lblV.Text = "--"; $lblV.Location = New-Object System.Drawing.Point(64, 8)
    $lblV.AutoSize = $true; $lblV.ForeColor = $colText
    $lblV.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)
    $card.Controls.Add($lblV)
    $lblL = New-Object System.Windows.Forms.Label
    $lblL.Text = $label; $lblL.Location = New-Object System.Drawing.Point(64, 46)
    $lblL.AutoSize = $true; $lblL.ForeColor = $colSub
    $lblL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
    $card.Controls.Add($lblL)
    $statBar.Controls.Add($card)
    $script:statCards[$key] = @{ Card=$card; Val=$lblV; Label=$lblL }
}
New-StatCard "del"  0   $colGreen  "🗑"  "可删空间（待你确认）"
New-StatCard "keep" 300 $colRed    "🛡"  "保留（系统/软件/个人）"
New-StatCard "jud"  600 $colYellow "🤔"  "需你判断"
New-StatCard "cnt"  900 $colBrand  "📁"  "已扫描目录"

# —— 分类筛选 chips（圆角胶囊） ——
$chipsBar = New-Object System.Windows.Forms.Panel
$chipsBar.Dock = "Top"; $chipsBar.Height = 52; $chipsBar.BackColor = $colBg
$chipsBar.Padding = New-Object System.Windows.Forms.Padding(24, 0, 0, 0)
$pageScan.Controls.Add($chipsBar)
$script:chipBtns = @{}
function New-Chip([string]$key, [int]$x, [string]$text) {
    $b = New-RoundBtn $text $x 9 96 32 "secondary"
    $b.Tag = $key
    $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $chipsBar.Controls.Add($b)
    $script:chipBtns[$key] = $b
    return $b
}
$script:catFilter = ""
$chipAll = New-Chip "all" 0 "全部"
$chipG   = New-Chip "G"   104 "🟢 可删"
$chipR   = New-Chip "R"   208 "🔴 保留"
$chipY   = New-Chip "Y"   312 "🟡 判断"

function Set-ChipState {
    foreach ($kk in @("all","G","R","Y")) {
        $bb = $script:chipBtns[$kk]
        $act = ($kk -eq $script:catFilter -or ($script:catFilter -eq "" -and $kk -eq "all"))
        $bb.BackColor = if ($act) { $colBrand } else { $colSurface }
        $bb.Invalidate()
    }
}
Set-ChipState

# —— 内容区：列表 + 条形图 ——
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = "Fill"; $split.SplitterDistance = 780; $split.BackColor = $colBg
$split.Panel1.BackColor = $colBg; $split.Panel2.BackColor = $colBg
$split.Panel1.Padding = New-Object System.Windows.Forms.Padding(24, 0, 8, 16)
$split.Panel2.Padding = New-Object System.Windows.Forms.Padding(8, 0, 24, 16)
$pageScan.Controls.Add($split)

$list = New-Object System.Windows.Forms.ListView
$list.Dock = "Fill"; $list.View = "Details"; $list.FullRowSelect = $true
$list.CheckBoxes = $true; $list.GridLines = $false; $list.BorderStyle = "None"
$list.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5)
$list.BackColor = $colSurface
$list.Columns.Add("目录", 260) | Out-Null
$list.Columns.Add("大小(MB)", 80) | Out-Null
$list.Columns.Add("分类", 90) | Out-Null
$list.Columns.Add("说明", 300) | Out-Null
$split.Panel1.Controls.Add($list)

# 右侧条形图卡片
$rightWrap = New-Object System.Windows.Forms.Panel
$rightWrap.Dock = "Fill"; $rightWrap.BackColor = $colBg
$split.Panel2.Controls.Add($rightWrap)

$chartCard = New-Card 0 0 340 560
$chartCard.Dock = "Fill"; $chartCard.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
$rightWrap.Controls.Add($chartCard)

$lblChartTitle = New-Object System.Windows.Forms.Label
$lblChartTitle.Text = "占用排行 Top 15"; $lblChartTitle.Dock = "Top"; $lblChartTitle.Height = 30
$lblChartTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Bold)
$lblChartTitle.ForeColor = $colText
$chartCard.Controls.Add($lblChartTitle)
$lblChartSub = New-Object System.Windows.Forms.Label
$lblChartSub.Text = "随搜索 / 筛选联动"; $lblChartSub.Dock = "Top"; $lblChartSub.Height = 20
$lblChartSub.ForeColor = $colMuted; $lblChartSub.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
$chartCard.Controls.Add($lblChartSub)

$chartBox = New-Object System.Windows.Forms.Panel
$chartBox.Dock = "Fill"; $chartBox.BackColor = $colSurface
$chartCard.Controls.Add($chartBox)

$script:chartData = @()
function Update-Chart {
    $script:chartData = @()
    $items = @()
    foreach ($it in $list.Items) {
        if ($it.Text -eq "") { continue }
        $items += [pscustomobject]@{ Name = $it.Text; SizeMB = [double]$it.SubItems[1].Text; Cat = $it.SubItems[2].Text }
    }
    $items = @($items | Where-Object { $_.Cat -ne "" } | Sort-Object SizeMB -Descending | Select-Object -First 15)
    if (@($items).Count -eq 0) { $chartBox.Invalidate(); return }
    $max = ($items | Measure-Object SizeMB -Maximum).Maximum
    foreach ($it in $items) {
        $script:chartData += [pscustomobject]@{ Name=$it.Name; SizeMB=$it.SizeMB; Cat=$it.Cat; Max=$max }
    }
    $chartBox.Invalidate()
}

$chartBox.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $w = $chartBox.ClientSize.Width; $h = $chartBox.ClientSize.Height
    $data = @($script:chartData)
    if ($data.Count -eq 0) {
        $emptyBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colMuted))
        $emptyFont = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
        $g.DrawString("扫描后在此显示目录占用排行", $emptyFont, $emptyBrush, 12, 14)
        $emptyBrush.Dispose(); $emptyFont.Dispose()
        return
    }
    $nameFont = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
    $valFont  = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $barH = 20; $gap = 9; $y = 10
    $nameW = 118
    $barLeft = 126
    $valW = 82
    $barRight = $w - $valW
    foreach ($d in $data) {
        $base = switch ($d.Cat) {
            "🔴保留" { $colRed } "🟢可删" { $colGreen } default { $colYellow }
        }
        $cBase = [System.Drawing.ColorTranslator]::FromHtml($base)
        $cLight = [System.Drawing.Color]::FromArgb(160, $cBase.R, $cBase.G, $cBase.B)
        $name = $d.Name
        if ($name.Length -gt 14) { $name = $name.Substring(0, 12) + "…" }
        $nameBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colSub))
        $g.DrawString($name, $nameFont, $nameBrush, 8, $y + 2)
        $nameBrush.Dispose()
        # 轨道
        $trackRect = New-Object System.Drawing.Rectangle($barLeft, $y + 1, [math]::Max(4, $barRight - $barLeft), $barH - 2)
        $trackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#F1F4F8"))
        $trackPath = New-RoundedPath $trackRect.X $trackRect.Y $trackRect.Width $trackRect.Height 5
        $g.FillPath($trackBrush, $trackPath)
        $trackBrush.Dispose(); $trackPath.Dispose()
        # 渐变条
        $bw = [math]::Max(10, [int](($d.SizeMB / $d.Max) * ($barRight - $barLeft)))
        $rect = New-Object System.Drawing.Rectangle($barLeft, $y + 1, $bw, $barH - 2)
        $path = New-RoundedPath $rect.X $rect.Y $rect.Width $rect.Height 5
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $cBase, $cLight, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $g.FillPath($brush, $path)
        $brush.Dispose(); $path.Dispose()
        # 数值
        $valBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colSub))
        $val = " $($d.SizeMB) MB"
        $g.DrawString($val, $valFont, $valBrush, $w - $valW + 2, $y + 1)
        $valBrush.Dispose()
        $y += $barH + $gap
    }
    $nameFont.Dispose(); $valFont.Dispose()
})

# ============ 页面 2：规则 ============
$pageRules = New-Object System.Windows.Forms.Panel
$pageRules.Dock = "Fill"; $pageRules.Hide(); $pageRules.BackColor = $colBg
$contentHost.Controls.Add($pageRules)

$rulesTop = New-Object System.Windows.Forms.Panel
$rulesTop.Dock = "Top"; $rulesTop.Height = 76; $rulesTop.BackColor = $colSurface
$pageRules.Controls.Add($rulesTop)
$lblRulesTitle = New-Object System.Windows.Forms.Label
$lblRulesTitle.Text = "分类规则 · 数据化配置"
$lblRulesTitle.Location = New-Object System.Drawing.Point(28, 14)
$lblRulesTitle.AutoSize = $true; $lblRulesTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 13, [System.Drawing.FontStyle]::Bold)
$lblRulesTitle.ForeColor = $colText
$rulesTop.Controls.Add($lblRulesTitle)
$lblRulesSub = New-Object System.Windows.Forms.Label
$lblRulesSub.Text = "匹配词命中即分类，可导出 / 导入 JSON 跨机复用"
$lblRulesSub.Location = New-Object System.Drawing.Point(30, 46); $lblRulesSub.AutoSize = $true
$lblRulesSub.ForeColor = $colSub; $lblRulesSub.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
$rulesTop.Controls.Add($lblRulesSub)

function New-FlatBtn([string]$text, [int]$x, [int]$y, [int]$w, [string]$bg = $colSurface) {
    $b = New-RoundBtn $text $x $y $w 34 "secondary"
    if ($bg -ne $colSurface) { $b.Tag = "primary" }
    $rulesTop.Controls.Add($b)
    return $b
}
$btnExport  = New-FlatBtn "导出配置" 830 20 110
$btnImport  = New-FlatBtn "导入配置" 952 20 110
$btnAddRule = New-FlatBtn "＋ 新增规则" 1074 20 130 "primary"

$ruleFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$ruleFlow.Dock = "Fill"; $ruleFlow.AutoScroll = $true
$ruleFlow.Padding = New-Object System.Windows.Forms.Padding(24)
$pageRules.Controls.Add($ruleFlow)

function New-RuleCard($rule) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Width = 216; $card.Height = 96; $card.Margin = New-Object System.Windows.Forms.Padding(8)
    $card.BackColor = $colSurface
    $accent = if ($rule.Cat -eq "R") { $colRed } elseif ($rule.Cat -eq "G") { $colGreen } else { $colYellow }
    $card.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path = New-RoundedPath 0 0 ($s.ClientSize.Width - 1) ($s.ClientSize.Height - 1) $radius
        $g.DrawPath((New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($colBorder))), $path)
        $path.Dispose()
    })
    $strip = New-Object System.Windows.Forms.Panel
    $strip.Dock = "Left"; $strip.Width = 4; $strip.BackColor = [System.Drawing.ColorTranslator]::FromHtml($accent)
    $card.Controls.Add($strip)
    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = $rule.Pattern; $lblP.Location = New-Object System.Drawing.Point(16, 10)
    $lblP.Size = New-Object System.Drawing.Size(190, 26); $lblP.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblP.ForeColor = $colText; $card.Controls.Add($lblP)
    $catTxt = switch ($rule.Cat) { "R" { "🔴 保留" } "G" { "🟢 可删" } default { "🟡 判断" } }
    $lblC = New-Object System.Windows.Forms.Label
    $lblC.Text = "$catTxt · $($rule.Risk)"
    $lblC.Location = New-Object System.Drawing.Point(16, 40); $lblC.AutoSize = $true
    $lblC.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($accent)
    $lblC.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $card.Controls.Add($lblC)
    $lblD = New-Object System.Windows.Forms.Label
    $lblD.Text = $rule.Desc; $lblD.Location = New-Object System.Drawing.Point(16, 64)
    $lblD.Size = New-Object System.Drawing.Size(190, 28); $lblD.ForeColor = $colSub
    $lblD.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
    $card.Controls.Add($lblD)
    return $card
}

function Refresh-RulePage {
    $ruleFlow.Controls.Clear()
    foreach ($r in $script:RULES) {
        $ruleFlow.Controls.Add((New-RuleCard $r))
    }
    $lblRulesTitle.Text = "分类规则 · 数据化配置（$($script:RULES.Count) 条）"
}

function Show-AddRule {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "新增规则"; $f.Size = New-Object System.Drawing.Size(460, 270); $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"; $f.MaximizeBox = $false; $f.BackColor = $colBg
    $f.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
    $l1 = New-Object System.Windows.Forms.Label; $l1.Text = "匹配词（路径包含该词即命中，小写）"; $l1.Location = New-Object System.Drawing.Point(24, 20); $l1.AutoSize = $true; $l1.ForeColor = $colSub; $f.Controls.Add($l1)
    $t1 = New-Object System.Windows.Forms.TextBox; $t1.Location = New-Object System.Drawing.Point(24, 46); $t1.Width = 400; $t1.BorderStyle = "FixedSingle"; $f.Controls.Add($t1)
    $l2 = New-Object System.Windows.Forms.Label; $l2.Text = "分类"; $l2.Location = New-Object System.Drawing.Point(24, 84); $l2.AutoSize = $true; $l2.ForeColor = $colSub; $f.Controls.Add($l2)
    $c2 = New-Object System.Windows.Forms.ComboBox; $c2.DropDownStyle = "DropDownList"; $c2.Location = New-Object System.Drawing.Point(24, 110); $c2.Width = 110; $c2.FlatStyle = "Flat"
    $c2.Items.Add("G 可删") | Out-Null; $c2.Items.Add("R 保留") | Out-Null; $c2.Items.Add("Y 判断") | Out-Null; $c2.SelectedIndex = 0; $f.Controls.Add($c2)
    $l3 = New-Object System.Windows.Forms.Label; $l3.Text = "风险级"; $l3.Location = New-Object System.Drawing.Point(170, 84); $l3.AutoSize = $true; $l3.ForeColor = $colSub; $f.Controls.Add($l3)
    $c3 = New-Object System.Windows.Forms.ComboBox; $c3.DropDownStyle = "DropDownList"; $c3.Location = New-Object System.Drawing.Point(170, 110); $c3.Width = 90; $c3.FlatStyle = "Flat"
    $c3.Items.Add("L1") | Out-Null; $c3.Items.Add("L2") | Out-Null; $c3.Items.Add("L3") | Out-Null; $c3.SelectedIndex = 1; $f.Controls.Add($c3)
    $l4 = New-Object System.Windows.Forms.Label; $l4.Text = "说明"; $l4.Location = New-Object System.Drawing.Point(24, 146); $l4.AutoSize = $true; $l4.ForeColor = $colSub; $f.Controls.Add($l4)
    $t4 = New-Object System.Windows.Forms.TextBox; $t4.Location = New-Object System.Drawing.Point(24, 172); $t4.Width = 400; $t4.BorderStyle = "FixedSingle"; $f.Controls.Add($t4)
    $btnOK = New-RoundBtn "确定" 210 216 90 32 "primary"
    $btnCancel = New-RoundBtn "取消" 312 216 90 32 "secondary"
    $f.Controls.Add($btnOK); $f.Controls.Add($btnCancel)
    $btnCancel.Add_Click({ $f.DialogResult = "Cancel"; $f.Close() })
    $btnOK.Add_Click({
        if (-not $t1.Text.Trim()) { [System.Windows.Forms.MessageBox]::Show("请填写匹配词", "提示"); return }
        $script:RULES += @{ Pattern = $t1.Text.Trim(); Cat = $c2.SelectedItem.Substring(0,1); Desc = $t4.Text.Trim(); Risk = $c3.SelectedItem }
        $f.DialogResult = "OK"; $f.Close()
    })
    [void]$f.ShowDialog()
    if ($f.DialogResult -eq "OK") { Refresh-RulePage }
}

$btnExport.Add_Click({ Export-Config })
$btnImport.Add_Click({ Import-Config })
$btnAddRule.Add_Click({ Show-AddRule })

# ============ 页面 3：关于 ============
$pageAbout = New-Object System.Windows.Forms.Panel
$pageAbout.Dock = "Fill"; $pageAbout.Hide(); $pageAbout.BackColor = $colBg
$contentHost.Controls.Add($pageAbout)

$aboutCard = New-Card 28 28 1180 640
$pageAbout.Controls.Add($aboutCard)
$lblAbout = New-Object System.Windows.Forms.Label
$lblAbout.Dock = "Fill"; $lblAbout.Padding = New-Object System.Windows.Forms.Padding(36)
$lblAbout.Text = @"
清盘侠 · 电脑文件可视化审计  v1.4

功能
  · 全盘扫描：目录占用 + 三档分类（🔴保留 / 🟢可删 / 🟡判断）
  · 搜索过滤：输入关键词实时过滤目录列表，条形图同步联动
  · 安全删除：勾选删除 → 优先进回收站；自动写入变更历史收据 ChangeHistory.txt
  · 规则管理：分类规则数据化（匹配词/分类/风险级/说明），支持新增、导出/导入 JSON 配置
  · 零依赖：仅需系统自带 PowerShell 5.1，客户机免安装
  · MCP 模式：任意 AI 客户端可通过 MCP 协议直接调用扫描/删除能力

安全设计
  · 永不触碰：系统目录、个人文件、杀毒软件、虚拟内存/休眠文件
  · 风险分级：L1 安全清理 / L2 需确认 / L3 绝不能动
  · 可追溯：每次删除写入收据，配合回收站可还原

开源
  · GitHub: github.com/hulufeng/qingpanxia  ·  个人免费 · 商用需授权
  · 借鉴 Winhance / Windows-MCP 思路（能力即工具/变更收据/搜索/配置迁移/数据化），代码全部原创
"@
$lblAbout.ForeColor = $colText
$lblAbout.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$aboutCard.Controls.Add($lblAbout)

# ---------- 导航切换 ----------
function Set-NavHighlight($btn) {
    foreach ($b in @($btnNavScan, $btnNavRules, $btnNavAbout)) {
        $sel = ($b -eq $btn)
        $b.BackColor = if ($sel) { $colSideH } else { $colSide }
        $b.ForeColor = if ($sel) { "White" } else { "#9AA6B8" }
        $b.Font = if ($sel) { New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold) } else { New-Object System.Drawing.Font("Microsoft YaHei UI", 10) }
        $name = $b.Tag
        if ($script:navInd.ContainsKey($name)) {
            $script:navInd[$name].BackColor = if ($sel) { $colBrand } else { $colSide }
        }
    }
}
function Show-Page([string]$name) {
    $pageScan.Visible = ($name -eq "scan")
    $pageRules.Visible = ($name -eq "rules")
    $pageAbout.Visible = ($name -eq "about")
    if ($name -eq "rules") { Refresh-RulePage }
}
$btnNavScan.Add_Click({ Set-NavHighlight $btnNavScan; Show-Page "scan" })
$btnNavRules.Add_Click({ Set-NavHighlight $btnNavRules; Show-Page "rules" })
$btnNavAbout.Add_Click({ Set-NavHighlight $btnNavAbout; Show-Page "about" })

# ---------- 共享状态 / 扫描 Runspace ----------
$script:shared = [hashtable]::Synchronized(@{
    Running = $false; Progress = 0; Current = ""; Done = $false
    Data = $null; Error = $null; Drive = ""; FileCount = 0
})

$scanScript = {
    param($drive, $rules, $shared)
    function Get-Category([string]$path, $rules) {
        $low = $path.ToLower()
        foreach ($r in $rules) { if ($r.Cat -eq "G" -and $low -like "*$($r.Pattern)*") { return @("G", $r.Desc) } }
        foreach ($r in $rules) { if ($r.Cat -eq "R" -and $low -like "*$($r.Pattern)*") { return @("R", $r.Desc) } }
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
                      Where-Object { $_.Name -notin @('$RECYCLE.BIN',"System Volume Information","Documents and Settings","Recovery","Boot") })
        $n = @($topDirs).Count
        for ($i = 0; $i -lt $n; $i++) {
            $d = $topDirs[$i]
            $shared.Progress = [int](($i + 1) / $n * 100)
            $shared.Current = $d.Name
            $s = Get-DirSizeMB $d.FullName $shared
            $c = Get-Category $d.FullName $rules
            [void]$results.Add([pscustomobject]@{ Name=$d.Name; Path=$d.FullName; SizeMB=$s; Cat=$c[0]; Desc=$c[1]; Level=0 })
            if ($c[0] -eq "R") {
                Get-ChildItem $d.FullName -Directory -Force -EA SilentlyContinue | ForEach-Object {
                    $c2 = Get-Category $_.FullName $rules
                    if ($c2[0] -eq "G") {
                        $ss = Get-DirSizeMB $_.FullName $shared
                        [void]$results.Add([pscustomobject]@{ Name="    " + $_.Name; Path=$_.FullName; SizeMB=$ss; Cat=$c2[0]; Desc=$c2[1]; Level=1 })
                    }
                }
            } else {
                Get-ChildItem $d.FullName -Directory -Force -EA SilentlyContinue | ForEach-Object {
                    $ss = Get-DirSizeMB $_.FullName $shared
                    if ($ss -gt 10) {
                        $c2 = Get-Category $_.FullName $rules
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
$script:allResults = $null

function Start-Scan {
    $drive = $cboDrive.SelectedItem
    if (-not $drive) { [System.Windows.Forms.MessageBox]::Show("请先选择盘符", "提示"); return }
    if ($script:shared.Running) { return }
    $list.Items.Clear(); $chartBox.Controls.Clear()
    $script:shared.Running = $true; $script:shared.Done = $false
    $script:shared.Progress = 0; $script:shared.Current = ""; $script:shared.Error = $null
    $script:shared.Data = $null; $script:shared.Drive = $drive; $script:shared.FileCount = 0
    $script:allResults = $null
    $btnScan.Enabled = $false
    Set-Status "扫描中…" "scan"
    $prog.Value = 0
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $script:ps = [powershell]::Create()
    $script:ps.Runspace = $runspace
    $null = $script:ps.AddScript($scanScript).AddArgument($drive).AddArgument($script:RULES).AddArgument($script:shared)
    $script:handle = $script:ps.BeginInvoke()
}

function Set-Status([string]$text, [string]$mode) {
    $lblStatus.Text = $text; $lblStatus.Visible = $true
    switch ($mode) {
        "scan"  { $lblStatus.BackColor = $colBrandL; $lblStatus.ForeColor = $colBrandD }
        "done"  { $lblStatus.BackColor = $colGreenL; $lblStatus.ForeColor = $colGreen }
        default { $lblStatus.BackColor = "#EDF0F5"; $lblStatus.ForeColor = $colSub }
    }
}

function Populate-List([string]$filter) {
    if ($null -eq $script:allResults) { return }
    $checkedSet = @{}
    foreach ($it in $list.Items) { if ($it.Checked) { $checkedSet[$it.Tag] = $true } }
    $list.BeginUpdate(); $list.Items.Clear()
    $sumG = 0; $cntG = 0; $sumR = 0; $cntY = 0
    foreach ($r in $script:allResults) {
        if ($r.Cat -eq "G") { $sumG += $r.SizeMB; $cntG++ }
        elseif ($r.Cat -eq "R") { $sumR += $r.SizeMB }
        else { $cntY++ }
        if ($filter) {
            $hay = ($r.Name + " " + $r.Desc + " " + $r.Path).ToLower()
            if ($hay -notlike "*$($filter.ToLower())*") { continue }
        }
        if ($script:catFilter -and $r.Cat -ne $script:catFilter) { continue }
        $catTxt = switch ($r.Cat) { "R" { "🔴保留" } "G" { "🟢可删" } default { "🟡判断" } }
        $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
        $item.Tag = $r.Path
        $item.SubItems.Add($r.SizeMB.ToString()) | Out-Null
        $item.SubItems.Add($catTxt) | Out-Null
        $item.SubItems.Add($r.Desc) | Out-Null
        if ($checkedSet.ContainsKey($r.Path)) { $item.Checked = $true }
        if ($r.Cat -eq "G") { $item.BackColor = $colGreenL }
        elseif ($r.Cat -eq "R") { $item.BackColor = $colRedL }
        else { $item.BackColor = $colYellowL }
        [void]$list.Items.Add($item)
    }
    $list.EndUpdate()
    $script:statCards["del"].Val.Text  = "$([math]::Round($sumG/1024,2)) GB · $cntG 项"
    $script:statCards["keep"].Val.Text = "$([math]::Round($sumR/1024,2)) GB"
    $script:statCards["jud"].Val.Text  = "$cntY 项"
    $script:statCards["cnt"].Val.Text  = "$(@($script:allResults).Count) 个"
    if ($filter) { Set-Status "已过滤「$filter」· 显示 $($list.Items.Count) 项" "idle" }
    else { Set-Status "扫描完成 · 可删约 $([math]::Round($sumG/1024,2)) GB（$cntG 项）" "done" }
    Update-Chart
}

# chips 点击
foreach ($ck in @("all","G","R","Y")) {
    $script:chipBtns[$ck].Add_Click({
        param($s, $e)
        $key = $s.Tag
        $script:catFilter = if ($key -eq "all") { "" } else { [string]$key }
        Set-ChipState
        Populate-List $txtSearch.Text.Trim()
    })
}

function Scan-Done {
    $btnScan.Enabled = $true
    if ($script:shared.Error) { Set-Status "扫描出错: $($script:shared.Error)" "idle"; return }
    $script:allResults = $script:shared.Data
    if ($null -eq $script:allResults) { Set-Status "扫描完成（无结果）" "done"; return }
    Populate-List ""
}

$btnScan.Add_Click({ Start-Scan })

$searchTimer = New-Object System.Windows.Forms.Timer
$searchTimer.Interval = 400
$searchTimer.Add_Tick({
    $searchTimer.Stop()
    Populate-List $txtSearch.Text.Trim()
})

# 底部操作栏（扫描页 Dock Bottom 需在 Fill 之前加入——用 Add 到 pageScan 底部）
$botBar = New-Object System.Windows.Forms.Panel
$botBar.Dock = "Bottom"; $botBar.Height = 64; $botBar.BackColor = $colSurface
$pageScan.Controls.Add($botBar)
$botBar.BringToFront()

$lblTip = New-Object System.Windows.Forms.Label
$lblTip.Text = "🟢 可删　🟡 需判断　🔴 保留　·　勾选后删除 → 优先进回收站，自动写变更收据"
$lblTip.Location = New-Object System.Drawing.Point(28, 22); $lblTip.AutoSize = $true
$lblTip.ForeColor = $colSub; $botBar.Controls.Add($lblTip)

$btnView = New-RoundBtn "查看删除记录" 830 14 132 36 "secondary"
$botBar.Controls.Add($btnView)

$btnDel = New-RoundBtn "删除勾选项（进回收站）" 974 14 210 36 "danger"
$btnDel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$botBar.Controls.Add($btnDel)

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
    $ok = 0; $rec = 0; $histLines = @()
    foreach ($p in $paths) {
        if (Test-Path $p) {
            if ([Recycle]::Send($p)) { $rec++ }
            else { Remove-Item $p -Recurse -Force -Confirm:$false }
            $ok++
            $szTxt = ""
            foreach ($it in $list.Items) { if ($it.Tag -eq $p) { $szTxt = $it.SubItems[1].Text; break } }
            $histLines += "$p ($szTxt MB)"
        }
    }
    if (@($histLines).Count -gt 0) {
        Add-HistoryBatch "删除 $(@($histLines).Count) 项（$rec 项进回收站，$($ok - $rec) 项永久删除）" $histLines
    }
    foreach ($item in @($list.Items | Where-Object { $_.Checked })) {
        $list.Items.Remove($item)
    }
    [System.Windows.Forms.MessageBox]::Show("删除完成：$ok 项，其中 $rec 项进入回收站`n`n已写入变更记录：$($script:historyFile)", "完成")
    Update-Chart
})

$btnView.Add_Click({ Show-History })

# UI 定时器
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    if ($script:shared.Running) {
        $prog.Value = $script:shared.Progress
        if ($script:shared.Current) {
            $fc = $script:shared.FileCount
            if ($fc -gt 0) { Set-Status "扫描中: $($script:shared.Current) · 已处理 $fc 个文件" "scan" }
            else { Set-Status "扫描中: $($script:shared.Current)" "scan" }
        }
        return
    }
    if ($script:shared.Done -and $script:ps -ne $null -and -not $script:ps.HadErrors) {
        try { $script:ps.EndInvoke($script:handle) } catch {}
        $script:ps.Dispose()
        $script:ps = $null
        $timer.Stop()
        Scan-Done
    }
})
$timer.Start()

$form.Add_Shown({
    $form.Activate()
    Set-NavHighlight $btnNavScan
    Refresh-RulePage
    if ($autoScan) {
        $cboDrive.SelectedItem = $autoScan
        Start-Scan
    }
})

[void]$form.ShowDialog()
