# pc-file-audit GUI —— 电脑文件可视化审计窗口（PowerShell + WinForms 零依赖版）
# =============================================================================
# 双击运行（或右键 -> 使用 PowerShell 运行）
# 功能：选择盘符 -> 扫描 -> 表格三档分类（红/绿/黄）+ 搜索过滤 -> 勾选删除（进回收站）
#       删除自动写变更历史收据（ChangeHistory.txt）；规则可导出/导入为 JSON 配置
# 借鉴：Winhance 的"变更历史收据/搜索过滤/配置导入导出/设置项数据化/分区导航"思路（原创代码，不抄其代码）
# 依赖：仅 Windows 自带 PowerShell 5.1 + .NET WinForms，客户机无需安装任何东西
# 编码：本文件须为 UTF-8 BOM（Windows PowerShell 5.1 兼容）
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 自动扫描参数：-AutoScan D: （启动后自动扫描指定盘，便于自动化验证）
$autoScan = $null
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq "-AutoScan") { $autoScan = $args[$i + 1] } }

# ---------- 分类规则（设置项数据化：Pattern / Cat / Desc / Risk） ----------
# Cat: R=必须保留  G=明确可删  Y=用户判断；Risk: L1安全清理 L2需确认 L3绝不能动
# 注意：PowerShell 双引号内反斜杠无需转义，路径分隔符直接写 \x
# 匹配顺序固定：先 G（可删）再 R（保留）——否则 \windows 会把 Windows\Temp 等缓存标成保留
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

# ---------- 变更历史收据（原创实现，借鉴"每次操作留痕"思路） ----------
# 每次删除把"时间 + 项目 + 大小"追加写入 ChangeHistory.txt（脚本同目录，UTF-8 BOM，CRLF）
# 配合回收站 = 每次清理都可追溯、可回滚
$script:historyFile = Join-Path $PSScriptRoot "ChangeHistory.txt"
function Add-HistoryBatch([string]$header, [string[]]$lines) {
    try {
        $encBom = New-Object System.Text.UTF8Encoding($true)   # 带 BOM（用于首次创建）
        $encNo  = New-Object System.Text.UTF8Encoding($false)  # 追加时不再写 BOM
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
        if (Test-Path $script:historyFile) {
            Start-Process notepad $script:historyFile
        } else {
            [System.Windows.Forms.MessageBox]::Show("还没有删除记录。勾选项目删除后会自动写入。", "变更历史")
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("打开记录失败: $($_.Exception.Message)", "提示")
    }
}

# ---------- 配置导出 / 导入（原创实现，借鉴"配置可迁移"思路） ----------
function Export-Config {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.FileName = "pc-file-audit-config.json"; $dlg.Filter = "JSON 配置文件 (*.json)|*.json"
    if ($dlg.ShowDialog() -ne "OK") { return }
    try {
        $cfg = [pscustomobject]@{ Version = 1; Updated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Rules = $script:RULES }
        $json = $cfg | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($dlg.FileName, $json, (New-Object System.Text.UTF8Encoding($true)))
        [System.Windows.Forms.MessageBox]::Show("已导出 $($script:RULES.Count) 条规则到：`n$($dlg.FileName)", "导出配置")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("导出失败: $($_.Exception.Message)", "提示")
    }
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
    } catch {
        [System.Windows.Forms.MessageBox]::Show("导入失败: $($_.Exception.Message)", "提示")
    }
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
        op.wFunc = 3; // FO_DELETE
        op.pFrom = path + "\0\0";
        op.fFlags = 0x40 | 0x10 | 0x4; // ALLOWUNDO | NOCONFIRMATION | SILENT
        return SHFileOperation(ref op) == 0;
    }
}
"@

# ---------- 配色主题（v1.2 现代视觉） ----------
$colBg    = "#F4F6FA"   # 主区浅灰蓝背景
$colCard  = "#FFFFFF"   # 卡片白
$colSide  = "#1F2A3D"   # 侧边栏深蓝灰
$colSideH = "#26354F"   # 侧边栏悬停/选中
$colBrand = "#14B8A6"   # 品牌青绿
$colBrandD= "#0D9488"   # 品牌深青
$colGreen = "#2FA84F"   # 可删绿
$colRed   = "#E5484D"   # 保留红
$colYellow= "#E8B339"   # 判断黄
$colText  = "#2C3E50"   # 主文字
$colSub   = "#7A8BA0"   # 次要文字

# ---------- 窗体 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "pc-file-audit · 电脑文件可视化审计 v1.3"
$form.Size = New-Object System.Drawing.Size(1240, 780)
$form.MinimumSize = New-Object System.Drawing.Size(1024, 640)
$form.StartPosition = "CenterScreen"
$form.BackColor = $colBg
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

# ---------- 左侧导航条（深色 + 选中指示条） ----------
$navBar = New-Object System.Windows.Forms.Panel
$navBar.Dock = "Left"; $navBar.Width = 156; $navBar.BackColor = $colSide
$form.Controls.Add($navBar)

$logoTop = New-Object System.Windows.Forms.Panel
$logoTop.Dock = "Top"; $logoTop.Height = 68; $logoTop.BackColor = $colSide
$navBar.Controls.Add($logoTop)
$lblLogo = New-Object System.Windows.Forms.Label
$lblLogo.Text = "PC 审计"; $lblLogo.Dock = "Top"; $lblLogo.Height = 34
$lblLogo.ForeColor = "White"; $lblLogo.TextAlign = "MiddleCenter"
$lblLogo.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)
$logoTop.Controls.Add($lblLogo)
$lblLogoSub = New-Object System.Windows.Forms.Label
$lblLogoSub.Text = "FILE AUDIT"; $lblLogoSub.Dock = "Top"; $lblLogoSub.Height = 20
$lblLogoSub.ForeColor = $colBrand; $lblLogoSub.TextAlign = "MiddleCenter"
$lblLogoSub.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$logoTop.Controls.Add($lblLogoSub)

$script:navInd = @{}
$lblNavGroup = New-Object System.Windows.Forms.Label
$lblNavGroup.Text = "功能"; $lblNavGroup.Location = New-Object System.Drawing.Point(18, 74)
$lblNavGroup.AutoSize = $true; $lblNavGroup.ForeColor = "#5A6B82"
$lblNavGroup.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8)
$navBar.Controls.Add($lblNavGroup)
function New-NavBtn([string]$text, [int]$top, [string]$name) {
    $ind = New-Object System.Windows.Forms.Panel
    $ind.Width = 4; $ind.Height = 42; $ind.Left = 0; $ind.Top = 0
    $ind.BackColor = $colBrand
    $script:navInd[$name] = $ind
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $colSideH
    $b.ForeColor = "#8FA2B8"; $b.BackColor = $colSide
    $b.TextAlign = "MiddleLeft"
    $b.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
    $b.Location = New-Object System.Drawing.Point(0, $top); $b.Width = 156; $b.Height = 42
    $b.Tag = $name
    $b.Controls.Add($ind)
    $navBar.Controls.Add($b)
    return $b
}
$btnNavScan  = New-NavBtn "  扫描" 92  "scan"
$btnNavRules = New-NavBtn "  规则" 138 "rules"
$btnNavAbout = New-NavBtn "  关于" 184 "about"

$navFooter = New-Object System.Windows.Forms.Label
$navFooter.Text = "v1.3 · 零依赖`n个人免费 · 商用需授权" 
$navFooter.Dock = "Bottom"; $navFooter.Height = 46
$navFooter.ForeColor = "#5A6B82"; $navFooter.TextAlign = "MiddleCenter"
$navFooter.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
$navBar.Controls.Add($navFooter)

$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Dock = "Fill"; $form.Controls.Add($contentHost)

# ============ 页面 1：扫描 ============
$pageScan = New-Object System.Windows.Forms.Panel
$pageScan.Dock = "Fill"; $contentHost.Controls.Add($pageScan)

$topBar = New-Object System.Windows.Forms.Panel
$topBar.Dock = "Top"; $topBar.Height = 68; $topBar.BackColor = $colCard
$pageScan.Controls.Add($topBar)

$lblDrive = New-Object System.Windows.Forms.Label
$lblDrive.Text = "盘符"; $lblDrive.Location = New-Object System.Drawing.Point(20, 24)
$lblDrive.AutoSize = $true; $lblDrive.ForeColor = $colSub; $topBar.Controls.Add($lblDrive)

$cboDrive = New-Object System.Windows.Forms.ComboBox
$cboDrive.DropDownStyle = "DropDownList"; $cboDrive.Location = New-Object System.Drawing.Point(60, 19)
$cboDrive.Width = 76; $cboDrive.FlatStyle = "Flat"
$topBar.Controls.Add($cboDrive)

Get-PSDrive -PSProvider FileSystem | ForEach-Object { $cboDrive.Items.Add($_.Name + ":") } | Out-Null
if ($cboDrive.Items.Count -gt 0) { $cboDrive.SelectedIndex = 0 }

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "开始扫描"; $btnScan.Location = New-Object System.Drawing.Point(152, 17)
$btnScan.Width = 108; $btnScan.Height = 34
$btnScan.FlatStyle = "Flat"; $btnScan.FlatAppearance.BorderSize = 0
$btnScan.FlatAppearance.MouseOverBackColor = $colBrandD
$btnScan.BackColor = $colBrand; $btnScan.ForeColor = "White"
$btnScan.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$topBar.Controls.Add($btnScan)

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "搜索"; $lblSearch.Location = New-Object System.Drawing.Point(286, 24)
$lblSearch.AutoSize = $true; $lblSearch.ForeColor = $colSub; $topBar.Controls.Add($lblSearch)
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(330, 19); $txtSearch.Width = 200
$txtSearch.BorderStyle = "FixedSingle"; $topBar.Controls.Add($txtSearch)

$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Location = New-Object System.Drawing.Point(556, 22); $prog.Width = 230; $prog.Height = 20
$prog.Style = "Continuous"; $topBar.Controls.Add($prog)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "就绪 · 选择盘符后点击开始扫描"; $lblStatus.Location = New-Object System.Drawing.Point(806, 18)
$lblStatus.AutoSize = $true; $lblStatus.ForeColor = $colSub
$lblStatus.BackColor = "#EDF0F5"
$lblStatus.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)
$topBar.Controls.Add($lblStatus)

$botBar = New-Object System.Windows.Forms.Panel
$botBar.Dock = "Bottom"; $botBar.Height = 60; $botBar.BackColor = $colCard
$pageScan.Controls.Add($botBar)

$lblTip = New-Object System.Windows.Forms.Label
$lblTip.Text = "🟢 可删  🟡 需判断  🔴 保留 — 勾选后删除，优先进回收站并自动写变更记录"
$lblTip.Location = New-Object System.Drawing.Point(20, 20); $lblTip.AutoSize = $true
$lblTip.ForeColor = $colSub; $botBar.Controls.Add($lblTip)

$btnView = New-Object System.Windows.Forms.Button
$btnView.Text = "查看删除记录"; $btnView.Location = New-Object System.Drawing.Point(780, 12)
$btnView.Width = 126; $btnView.Height = 36
$btnView.FlatStyle = "Flat"; $btnView.FlatAppearance.BorderColor = "#D5DDE8"
$btnView.BackColor = $colCard; $btnView.ForeColor = $colText
$botBar.Controls.Add($btnView)

$btnDel = New-Object System.Windows.Forms.Button
$btnDel.Text = "删除勾选项（进回收站）"; $btnDel.Location = New-Object System.Drawing.Point(920, 12)
$btnDel.Width = 200; $btnDel.Height = 36
$btnDel.FlatStyle = "Flat"; $btnDel.FlatAppearance.BorderSize = 0
$btnDel.FlatAppearance.MouseOverBackColor = "#278D42"
$btnDel.BackColor = $colGreen; $btnDel.ForeColor = "White"
$btnDel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$botBar.Controls.Add($btnDel)

# ---------- 统计概览卡（借鉴 WinUtil/仪表盘：4 张指标卡） ----------
$statBar = New-Object System.Windows.Forms.Panel
$statBar.Dock = "Top"; $statBar.Height = 76; $statBar.BackColor = $colBg
$pageScan.Controls.Add($statBar)

$script:statCards = @{}
function New-StatCard([string]$key, [int]$x, [string]$accent, [string]$label, [string]$val) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point($x, 12); $card.Width = 248; $card.Height = 52
    $card.BackColor = $colCard; $card.BorderStyle = "FixedSingle"
    $strip = New-Object System.Windows.Forms.Panel
    $strip.Dock = "Left"; $strip.Width = 5; $strip.BackColor = [System.Drawing.ColorTranslator]::FromHtml($accent)
    $card.Controls.Add($strip)
    $lblV = New-Object System.Windows.Forms.Label
    $lblV.Text = $val; $lblV.Location = New-Object System.Drawing.Point(18, 4)
    $lblV.AutoSize = $true; $lblV.ForeColor = $colText
    $lblV.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)
    $card.Controls.Add($lblV)
    $lblL = New-Object System.Windows.Forms.Label
    $lblL.Text = $label; $lblL.Location = New-Object System.Drawing.Point(18, 30)
    $lblL.AutoSize = $true; $lblL.ForeColor = $colSub
    $lblL.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
    $card.Controls.Add($lblL)
    $statBar.Controls.Add($card)
    $script:statCards[$key] = @{ Card=$card; Val=$lblV; Label=$lblL }
}
New-StatCard "del"  12  $colGreen  "可删空间（待你确认）"  "--"
New-StatCard "keep" 272 $colRed    "保留（系统/软件/个人）" "--"
New-StatCard "jud"  532 $colYellow "需你判断"                "--"
New-StatCard "cnt"  792 $colBrand  "已扫描目录"              "--"

# ---------- 分类筛选 chips（借鉴 WinUtil：点击高亮筛选） ----------
$chipsBar = New-Object System.Windows.Forms.Panel
$chipsBar.Dock = "Top"; $chipsBar.Height = 44; $chipsBar.BackColor = $colBg
$pageScan.Controls.Add($chipsBar)
$script:chipBtns = @{}
function New-Chip([string]$key, [int]$x, [string]$text, [bool]$active) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, 7); $b.Width = 92; $b.Height = 30
    $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
    $b.Tag = $key
    if ($active) { $b.BackColor = $colBrand; $b.ForeColor = "White"; $b.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold) }
    else { $b.BackColor = $colCard; $b.ForeColor = $colSub; $b.FlatAppearance.BorderColor = "#D5DDE8" }
    $chipsBar.Controls.Add($b)
    $script:chipBtns[$key] = $b
    return $b
}
$script:catFilter = ""
New-Chip "all" 12 "全部" $true
New-Chip "G"  112 "🟢 可删" $false
New-Chip "R"  212 "🔴 保留" $false
New-Chip "Y"  312 "🟡 判断" $false

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = "Fill"; $split.SplitterDistance = 740; $split.Panel1.BackColor = $colBg; $split.Panel2.BackColor = $colBg
$pageScan.Controls.Add($split)

$list = New-Object System.Windows.Forms.ListView
$list.Dock = "Fill"; $list.View = "Details"; $list.FullRowSelect = $true
$list.CheckBoxes = $true; $list.GridLines = $false; $list.BorderStyle = "None"
$list.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9.5)
$list.Columns.Add("目录", 240) | Out-Null
$list.Columns.Add("大小(MB)", 88) | Out-Null
$list.Columns.Add("分类", 84) | Out-Null
$list.Columns.Add("说明", 320) | Out-Null
$split.Panel1.Controls.Add($list)

$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Dock = "Fill"; $split.Panel2.Controls.Add($rightPanel)

$lblChartTitle = New-Object System.Windows.Forms.Label
$lblChartTitle.Text = "目录占用 Top15（随搜索联动）"; $lblChartTitle.Dock = "Top"
$lblChartTitle.Height = 36; $lblChartTitle.Padding = New-Object System.Windows.Forms.Padding(12, 6, 0, 0)
$lblChartTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Bold)
$lblChartTitle.ForeColor = $colText
$rightPanel.Controls.Add($lblChartTitle)

$chartBox = New-Object System.Windows.Forms.Panel
$chartBox.Dock = "Fill"; $chartBox.BackColor = $colCard; $chartBox.Padding = New-Object System.Windows.Forms.Padding(8)
$rightPanel.Controls.Add($chartBox)

# 条形图数据（自绘：圆角渐变条 + 名称 + 数值）
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

Add-Type -AssemblyName System.Drawing
$chartBox.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $w = $chartBox.ClientSize.Width; $h = $chartBox.ClientSize.Height
    $data = @($script:chartData)
    if ($data.Count -eq 0) {
        $emptyBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#B8C4D4"))
        $emptyFont = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
        $g.DrawString("扫描后在此显示目录占用排行", $emptyFont, $emptyBrush, 14, 16)
        $emptyBrush.Dispose(); $emptyFont.Dispose()
        return
    }
    $nameFont = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $valFont  = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $barH = 22; $gap = 10; $y = 12
    $nameW = 122                      # 名称区宽度
    $barLeft = 136                    # 条起点
    $valW = 88                        # 数值区宽度（右侧固定）
    $barRight = $w - $valW
    foreach ($d in $data) {
        $base = switch ($d.Cat) {
            "🔴保留" { $colRed } "🟢可删" { $colGreen } default { $colYellow }
        }
        $cBase = [System.Drawing.ColorTranslator]::FromHtml($base)
        $cLight = [System.Drawing.Color]::FromArgb(220, $cBase.R, $cBase.G, $cBase.B)
        # 名称（按宽度截断防溢出）
        $name = $d.Name
        if ($name.Length -gt 15) { $name = $name.Substring(0, 13) + "…" }
        $nameBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colText))
        $g.DrawString($name, $nameFont, $nameBrush, 10, $y + 2)
        $nameBrush.Dispose()
        # 圆角渐变条
        $bw = [math]::Max(12, [int](($d.SizeMB / $d.Max) * ($barRight - $barLeft)))
        $rect = New-Object System.Drawing.Rectangle($barLeft, $y, $bw, $barH)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $r = 6
        $path.AddArc($rect.X, $rect.Y, $r * 2, $r * 2, 180, 90)
        $path.AddArc($rect.Right - $r * 2, $rect.Y, $r * 2, $r * 2, 270, 90)
        $path.AddArc($rect.Right - $r * 2, $rect.Bottom - $r * 2, $r * 2, $r * 2, 0, 90)
        $path.AddArc($rect.X, $rect.Bottom - $r * 2, $r * 2, $r * 2, 90, 90)
        $path.CloseFigure()
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $cBase, $cLight, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $g.FillPath($brush, $path)
        $brush.Dispose(); $path.Dispose()
        # 数值（右侧固定区，条尾不重叠）
        $valBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colSub))
        $val = " $($d.SizeMB) MB"
        $g.DrawString($val, $valFont, $valBrush, $w - $valW + 2, $y + 2)
        $valBrush.Dispose()
        $y += $barH + $gap
    }
    $nameFont.Dispose(); $valFont.Dispose()
})

# ============ 页面 2：规则（设置项数据化展示 + 配置导入导出） ============
$pageRules = New-Object System.Windows.Forms.Panel
$pageRules.Dock = "Fill"; $pageRules.Hide(); $pageRules.BackColor = $colBg
$contentHost.Controls.Add($pageRules)

$rulesTop = New-Object System.Windows.Forms.Panel
$rulesTop.Dock = "Top"; $rulesTop.Height = 64; $rulesTop.BackColor = $colCard
$pageRules.Controls.Add($rulesTop)

$lblRulesTitle = New-Object System.Windows.Forms.Label
$lblRulesTitle.Text = "分类规则（设置项数据化：匹配词 · 分类 · 风险级 · 说明）"
$lblRulesTitle.Location = New-Object System.Drawing.Point(20, 20)
$lblRulesTitle.AutoSize = $true; $lblRulesTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Bold)
$lblRulesTitle.ForeColor = $colText
$rulesTop.Controls.Add($lblRulesTitle)

function New-FlatBtn([string]$text, [int]$x, [int]$y, [int]$w, [string]$bg = $colCard) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Width = $w; $b.Height = 34
    $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderColor = "#D5DDE8"
    $b.FlatAppearance.MouseOverBackColor = "#EEF2F8"
    $b.BackColor = $bg; $b.ForeColor = $colText
    $rulesTop.Controls.Add($b)
    return $b
}
$btnExport  = New-FlatBtn "导出配置" 700 15 104
$btnImport  = New-FlatBtn "导入配置" 816 15 104
$btnAddRule = New-FlatBtn "＋ 新增规则" 932 15 116 $colBrand
$btnAddRule.ForeColor = "White"
$btnAddRule.FlatAppearance.BorderSize = 0
$btnAddRule.FlatAppearance.MouseOverBackColor = $colBrandD

# 规则卡片流（借鉴"卡片式布局"思路）
$ruleFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$ruleFlow.Dock = "Fill"; $ruleFlow.AutoScroll = $true
$ruleFlow.Padding = New-Object System.Windows.Forms.Padding(16)
$pageRules.Controls.Add($ruleFlow)

function New-RuleCard($rule) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Width = 212; $card.Height = 96; $card.Margin = New-Object System.Windows.Forms.Padding(8)
    $card.BackColor = $colCard; $card.BorderStyle = "FixedSingle"
    $accent = if ($rule.Cat -eq "R") { $colRed } elseif ($rule.Cat -eq "G") { $colGreen } else { $colYellow }
    # 左侧色条
    $strip = New-Object System.Windows.Forms.Panel
    $strip.Dock = "Left"; $strip.Width = 6; $strip.BackColor = [System.Drawing.ColorTranslator]::FromHtml($accent)
    $card.Controls.Add($strip)
    # 规则名
    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = $rule.Pattern; $lblP.Location = New-Object System.Drawing.Point(14, 8)
    $lblP.Size = New-Object System.Drawing.Size(186, 26); $lblP.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblP.ForeColor = $colText; $card.Controls.Add($lblP)
    # 分类 + 风险（做成胶囊感）
    $catTxt = switch ($rule.Cat) { "R" { "🔴 保留" } "G" { "🟢 可删" } default { "🟡 判断" } }
    $lblC = New-Object System.Windows.Forms.Label
    $lblC.Text = "$catTxt · $($rule.Risk)"
    $lblC.Location = New-Object System.Drawing.Point(14, 38); $lblC.AutoSize = $true
    $lblC.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($accent)
    $lblC.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $card.Controls.Add($lblC)
    # 说明
    $lblD = New-Object System.Windows.Forms.Label
    $lblD.Text = $rule.Desc; $lblD.Location = New-Object System.Drawing.Point(14, 62)
    $lblD.Size = New-Object System.Drawing.Size(186, 28); $lblD.ForeColor = $colSub
    $lblD.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $card.Controls.Add($lblD)
    return $card
}

function Refresh-RulePage {
    $ruleFlow.Controls.Clear()
    foreach ($r in $script:RULES) {
        $ruleFlow.Controls.Add((New-RuleCard $r))
    }
    $lblRulesTitle.Text = "分类规则（$($script:RULES.Count) 条 · 设置项数据化）"
}

# 新增规则对话框
function Show-AddRule {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "新增规则"; $f.Size = New-Object System.Drawing.Size(440, 260); $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"; $f.MaximizeBox = $false; $f.BackColor = $colBg
    $f.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
    $l1 = New-Object System.Windows.Forms.Label; $l1.Text = "匹配词（路径包含该词即命中，小写）"; $l1.Location = New-Object System.Drawing.Point(20, 18); $l1.AutoSize = $true; $l1.ForeColor = $colSub; $f.Controls.Add($l1)
    $t1 = New-Object System.Windows.Forms.TextBox; $t1.Location = New-Object System.Drawing.Point(20, 44); $t1.Width = 380; $t1.BorderStyle = "FixedSingle"; $f.Controls.Add($t1)
    $l2 = New-Object System.Windows.Forms.Label; $l2.Text = "分类"; $l2.Location = New-Object System.Drawing.Point(20, 80); $l2.AutoSize = $true; $l2.ForeColor = $colSub; $f.Controls.Add($l2)
    $c2 = New-Object System.Windows.Forms.ComboBox; $c2.DropDownStyle = "DropDownList"; $c2.Location = New-Object System.Drawing.Point(20, 106); $c2.Width = 120; $c2.FlatStyle = "Flat"
    $c2.Items.Add("G 可删") | Out-Null; $c2.Items.Add("R 保留") | Out-Null; $c2.Items.Add("Y 判断") | Out-Null; $c2.SelectedIndex = 0; $f.Controls.Add($c2)
    $l3 = New-Object System.Windows.Forms.Label; $l3.Text = "风险级"; $l3.Location = New-Object System.Drawing.Point(170, 80); $l3.AutoSize = $true; $l3.ForeColor = $colSub; $f.Controls.Add($l3)
    $c3 = New-Object System.Windows.Forms.ComboBox; $c3.DropDownStyle = "DropDownList"; $c3.Location = New-Object System.Drawing.Point(170, 106); $c3.Width = 90; $c3.FlatStyle = "Flat"
    $c3.Items.Add("L1") | Out-Null; $c3.Items.Add("L2") | Out-Null; $c3.Items.Add("L3") | Out-Null; $c3.SelectedIndex = 1; $f.Controls.Add($c3)
    $l4 = New-Object System.Windows.Forms.Label; $l4.Text = "说明"; $l4.Location = New-Object System.Drawing.Point(20, 142); $l4.AutoSize = $true; $l4.ForeColor = $colSub; $f.Controls.Add($l4)
    $t4 = New-Object System.Windows.Forms.TextBox; $t4.Location = New-Object System.Drawing.Point(20, 168); $t4.Width = 380; $t4.BorderStyle = "FixedSingle"; $f.Controls.Add($t4)
    $btnOK = New-Object System.Windows.Forms.Button; $btnOK.Text = "确定"; $btnOK.Location = New-Object System.Drawing.Point(150, 212); $btnOK.Width = 80; $btnOK.Height = 32
    $btnOK.FlatStyle = "Flat"; $btnOK.FlatAppearance.BorderSize = 0; $btnOK.BackColor = $colBrand; $btnOK.ForeColor = "White"
    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = "取消"; $btnCancel.Location = New-Object System.Drawing.Point(240, 212); $btnCancel.Width = 80; $btnCancel.Height = 32
    $btnCancel.FlatStyle = "Flat"; $btnCancel.FlatAppearance.BorderColor = "#D5DDE8"; $btnCancel.BackColor = $colCard; $btnCancel.ForeColor = $colText
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

$lblAbout = New-Object System.Windows.Forms.Label
$lblAbout.AutoSize = $false; $lblAbout.Dock = "Fill"
$lblAbout.Padding = New-Object System.Windows.Forms.Padding(32)
$lblAbout.Text = @"
pc-file-audit · 电脑文件可视化审计  v1.3

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
  · GitHub: github.com/hulufeng/pc-file-audit  ·  个人免费 · 商用需授权
  · 借鉴 Winhance / Windows-MCP 思路（能力即工具/变更收据/搜索/配置迁移/数据化），代码全部原创
"@
$lblAbout.ForeColor = $colText
$lblAbout.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$pageAbout.Controls.Add($lblAbout)

# ---------- 导航切换 ----------
function Set-NavHighlight($btn) {
    foreach ($b in @($btnNavScan, $btnNavRules, $btnNavAbout)) {
        $sel = ($b -eq $btn)
        $b.BackColor = if ($sel) { $colSideH } else { $colSide }
        $b.ForeColor = if ($sel) { "White" } else { "#8FA2B8" }
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

# ---------- 共享状态（后台线程写入，UI Timer 读取） ----------
$script:shared = [hashtable]::Synchronized(@{
    Running = $false; Progress = 0; Current = ""; Done = $false
    Data = $null; Error = $null; Drive = ""; FileCount = 0
})

# ---------- 扫描脚本（在独立 Runspace 中执行，可调用函数） ----------
$scanScript = {
    param($drive, $rules, $shared)
    function Get-Category([string]$path, $rules) {
        $low = $path.ToLower()
        # 先查可删规则再查保留规则：否则 \windows 会把 Windows\Temp 等缓存也标成保留
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
$script:allResults = $null   # 扫描原始结果（搜索过滤基于它重建）

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

# 状态徽章（带底色胶囊）
function Set-Status([string]$text, [string]$mode) {
    $lblStatus.Text = $text
    switch ($mode) {
        "scan"  { $lblStatus.BackColor = "#E0F5F4"; $lblStatus.ForeColor = $colBrandD }
        "done"  { $lblStatus.BackColor = "#EAF7EE"; $lblStatus.ForeColor = $colGreen }
        default { $lblStatus.BackColor = "#EDF0F5"; $lblStatus.ForeColor = $colSub }
    }
}

# 填充列表（可带搜索关键词过滤，保留勾选状态；支持分类 chip 筛选）
function Populate-List([string]$filter) {
    if ($null -eq $script:allResults) { return }
    # 收集当前勾选，重建后恢复
    $checkedSet = @{}
    foreach ($it in $list.Items) { if ($it.Checked) { $checkedSet[$it.Tag] = $true } }
    $list.BeginUpdate(); $list.Items.Clear()
    $sumG = 0; $cntG = 0; $sumR = 0; $cntY = 0
    foreach ($r in $script:allResults) {
        # 统计卡基于全量计算（不受筛选影响）
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
        if ($r.Cat -eq "G") { $item.BackColor = "#EAF7EE" }
        elseif ($r.Cat -eq "R") { $item.BackColor = "#FBEFF0" }
        else { $item.BackColor = "#FBF3E2" }
        [void]$list.Items.Add($item)
    }
    $list.EndUpdate()
    # 统计概览卡
    $script:statCards["del"].Val.Text  = "$([math]::Round($sumG/1024,2)) GB · $cntG 项"
    $script:statCards["keep"].Val.Text = "$([math]::Round($sumR/1024,2)) GB"
    $script:statCards["jud"].Val.Text  = "$cntY 项"
    $script:statCards["cnt"].Val.Text  = "$(@($script:allResults).Count) 个"
    # 状态徽章
    if ($filter) { Set-Status "已过滤「$filter」· 显示 $($list.Items.Count) 项" "idle" }
    else { Set-Status "扫描完成 · 可删约 $([math]::Round($sumG/1024,2)) GB（$cntG 项）" "done" }
    Update-Chart
}

# 分类筛选 chip 点击
foreach ($ck in @("all","G","R","Y")) {
    $script:chipBtns[$ck].Add_Click({
        param($s, $e)
        $key = $s.Tag
        $script:catFilter = if ($key -eq "all") { "" } else { [string]$key }
        foreach ($kk in @("all","G","R","Y")) {
            $bb = $script:chipBtns[$kk]
            $act = ($kk -eq $key)
            $bb.BackColor = if ($act) { $colBrand } else { $colCard }
            $bb.ForeColor = if ($act) { "White" } else { $colSub }
            $bb.Font = if ($act) { New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold) } else { New-Object System.Drawing.Font("Microsoft YaHei UI", 9) }
        }
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

# 搜索实时过滤（借助 Timer 防抖，避免每敲一个字重建列表）
$searchTimer = New-Object System.Windows.Forms.Timer
$searchTimer.Interval = 400
$searchTimer.Add_Tick({
    $searchTimer.Stop()
    Populate-List $txtSearch.Text.Trim()
})
$txtSearch.Add_TextChanged({ $searchTimer.Stop(); $searchTimer.Start() })

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

# UI 定时器：轮询共享状态刷新进度条 / 完成时填充结果
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
    Set-NavHighlight $btnNavScan
    Refresh-RulePage
    if ($autoScan) {
        $cboDrive.SelectedItem = $autoScan
        Start-Scan
    }
})

[void]$form.ShowDialog()
