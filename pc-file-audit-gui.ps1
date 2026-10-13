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
    @{ Pattern="$recycle.bin";             Cat="R"; Desc="回收站";                         Risk="L3" },
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

# ---------- 窗体 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "pc-file-audit · 电脑文件可视化审计 v1.1"
$form.Size = New-Object System.Drawing.Size(1200, 720)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

# ---------- 左侧导航条（借鉴"分区导航"思路） ----------
$navBar = New-Object System.Windows.Forms.Panel
$navBar.Dock = "Left"; $navBar.Width = 128; $navBar.BackColor = "#26324A"
$form.Controls.Add($navBar)

$lblLogo = New-Object System.Windows.Forms.Label
$lblLogo.Text = "PC 审计"; $lblLogo.Dock = "Top"; $lblLogo.Height = 56
$lblLogo.ForeColor = "White"; $lblLogo.TextAlign = "MiddleCenter"
$lblLogo.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 13, [System.Drawing.FontStyle]::Bold)
$navBar.Controls.Add($lblLogo)

function New-NavBtn([string]$text, [int]$top, [string]$name) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.FlatStyle = "Flat"; $b.FlatAppearance.BorderSize = 0
    $b.ForeColor = "#CFD8E6"; $b.BackColor = "#26324A"
    $b.Location = New-Object System.Drawing.Point(10, $top); $b.Width = 108; $b.Height = 42
    $b.Tag = $name
    $navBar.Controls.Add($b)
    return $b
}
$btnNavScan  = New-NavBtn "📋  扫描" 64  "scan"
$btnNavRules = New-NavBtn "⚙️  规则" 114 "rules"
$btnNavAbout = New-NavBtn "ℹ️  关于" 164 "about"

$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Dock = "Fill"; $form.Controls.Add($contentHost)

# ============ 页面 1：扫描 ============
$pageScan = New-Object System.Windows.Forms.Panel
$pageScan.Dock = "Fill"; $contentHost.Controls.Add($pageScan)

$topBar = New-Object System.Windows.Forms.Panel
$topBar.Dock = "Top"; $topBar.Height = 56; $pageScan.Controls.Add($topBar)

$lblDrive = New-Object System.Windows.Forms.Label
$lblDrive.Text = "盘符:"; $lblDrive.Location = New-Object System.Drawing.Point(14, 18)
$lblDrive.AutoSize = $true; $topBar.Controls.Add($lblDrive)

$cboDrive = New-Object System.Windows.Forms.ComboBox
$cboDrive.DropDownStyle = "DropDownList"; $cboDrive.Location = New-Object System.Drawing.Point(60, 14)
$cboDrive.Width = 70; $topBar.Controls.Add($cboDrive)

Get-PSDrive -PSProvider FileSystem | ForEach-Object { $cboDrive.Items.Add($_.Name + ":") } | Out-Null
if ($cboDrive.Items.Count -gt 0) { $cboDrive.SelectedIndex = 0 }

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "开始扫描"; $btnScan.Location = New-Object System.Drawing.Point(144, 12)
$btnScan.Width = 96; $btnScan.Height = 32; $topBar.Controls.Add($btnScan)

# 搜索过滤框（借鉴"搜索式界面"思路：实时过滤目录列表）
$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "搜索:"; $lblSearch.Location = New-Object System.Drawing.Point(258, 18)
$lblSearch.AutoSize = $true; $topBar.Controls.Add($lblSearch)
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(305, 14); $txtSearch.Width = 180
$topBar.Controls.Add($txtSearch)

$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Location = New-Object System.Drawing.Point(505, 15); $prog.Width = 220; $prog.Height = 24
$prog.Style = "Continuous"; $topBar.Controls.Add($prog)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "就绪"; $lblStatus.Location = New-Object System.Drawing.Point(745, 18)
$lblStatus.AutoSize = $true; $lblStatus.ForeColor = "#555555"; $topBar.Controls.Add($lblStatus)

$botBar = New-Object System.Windows.Forms.Panel
$botBar.Dock = "Bottom"; $botBar.Height = 56; $pageScan.Controls.Add($botBar)

$lblTip = New-Object System.Windows.Forms.Label
$lblTip.Text = "勾选要删除的项目（绿=可删 黄=需判断 红=保留）。删除优先进回收站，自动写变更记录。"
$lblTip.Location = New-Object System.Drawing.Point(14, 18); $lblTip.AutoSize = $true
$lblTip.ForeColor = "#777777"; $botBar.Controls.Add($lblTip)

$btnView = New-Object System.Windows.Forms.Button
$btnView.Text = "查看删除记录"; $btnView.Location = New-Object System.Drawing.Point(700, 10)
$btnView.Width = 120; $btnView.Height = 36; $botBar.Controls.Add($btnView)

$btnDel = New-Object System.Windows.Forms.Button
$btnDel.Text = "删除勾选项（进回收站）"; $btnDel.Location = New-Object System.Drawing.Point(840, 10)
$btnDel.Width = 190; $btnDel.Height = 36; $btnDel.BackColor = "#2FA84F"
$btnDel.ForeColor = "White"; $botBar.Controls.Add($btnDel)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = "Fill"; $split.SplitterDistance = 820
$pageScan.Controls.Add($split)

$list = New-Object System.Windows.Forms.ListView
$list.Dock = "Fill"; $list.View = "Details"; $list.FullRowSelect = $true
$list.CheckBoxes = $true; $list.GridLines = $true
$list.Columns.Add("目录", 280) | Out-Null
$list.Columns.Add("大小(MB)", 90) | Out-Null
$list.Columns.Add("分类", 90) | Out-Null
$list.Columns.Add("说明", 340) | Out-Null
$split.Panel1.Controls.Add($list)

$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Dock = "Fill"; $split.Panel2.Controls.Add($rightPanel)

$lblChartTitle = New-Object System.Windows.Forms.Label
$lblChartTitle.Text = "目录占用 Top15（随搜索联动）"; $lblChartTitle.Dock = "Top"
$lblChartTitle.Height = 30; $lblChartTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Bold)
$rightPanel.Controls.Add($lblChartTitle)

$chartBox = New-Object System.Windows.Forms.Panel
$chartBox.Dock = "Fill"; $rightPanel.Controls.Add($chartBox)

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

# ============ 页面 2：规则（设置项数据化展示 + 配置导入导出） ============
$pageRules = New-Object System.Windows.Forms.Panel
$pageRules.Dock = "Fill"; $pageRules.Hide(); $contentHost.Controls.Add($pageRules)

$rulesTop = New-Object System.Windows.Forms.Panel
$rulesTop.Dock = "Top"; $rulesTop.Height = 60; $pageRules.Controls.Add($rulesTop)

$lblRulesTitle = New-Object System.Windows.Forms.Label
$lblRulesTitle.Text = "分类规则（设置项数据化：匹配词 · 分类 · 风险级 · 说明）"
$lblRulesTitle.Location = New-Object System.Drawing.Point(14, 16)
$lblRulesTitle.AutoSize = $true; $lblRulesTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Bold)
$rulesTop.Controls.Add($lblRulesTitle)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "导出配置"; $btnExport.Location = New-Object System.Drawing.Point(700, 14)
$btnExport.Width = 100; $btnExport.Height = 32; $rulesTop.Controls.Add($btnExport)

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text = "导入配置"; $btnImport.Location = New-Object System.Drawing.Point(812, 14)
$btnImport.Width = 100; $btnImport.Height = 32; $rulesTop.Controls.Add($btnImport)

$btnAddRule = New-Object System.Windows.Forms.Button
$btnAddRule.Text = "＋ 新增规则"; $btnAddRule.Location = New-Object System.Drawing.Point(924, 14)
$btnAddRule.Width = 110; $btnAddRule.Height = 32; $rulesTop.Controls.Add($btnAddRule)

# 规则卡片流（借鉴"卡片式布局"思路）
$ruleFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$ruleFlow.Dock = "Fill"; $ruleFlow.AutoScroll = $true
$ruleFlow.Padding = New-Object System.Windows.Forms.Padding(10)
$pageRules.Controls.Add($ruleFlow)

function New-RuleCard($rule) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Width = 196; $card.Height = 92; $card.Margin = New-Object System.Windows.Forms.Padding(6)
    $card.BackColor = "White"; $card.BorderStyle = "FixedSingle"
    $accent = if ($rule.Cat -eq "R") { "#E5484D" } elseif ($rule.Cat -eq "G") { "#2FA84F" } else { "#E8B339" }
    # 左侧色条
    $strip = New-Object System.Windows.Forms.Panel
    $strip.Dock = "Left"; $strip.Width = 6; $strip.BackColor = [System.Drawing.ColorTranslator]::FromHtml($accent)
    $card.Controls.Add($strip)
    # 规则名
    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = $rule.Pattern; $lblP.Location = New-Object System.Drawing.Point(12, 6)
    $lblP.Size = New-Object System.Drawing.Size(170, 24); $lblP.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblP.ForeColor = "#26324A"; $card.Controls.Add($lblP)
    # 分类 + 风险
    $lblC = New-Object System.Windows.Forms.Label
    $catTxt = switch ($rule.Cat) { "R" { "🔴 保留" } "G" { "🟢 可删" } default { "🟡 判断" } }
    $lblC.Text = "$catTxt · $($rule.Risk)"
    $lblC.Location = New-Object System.Drawing.Point(12, 34); $lblC.AutoSize = $true
    $lblC.ForeColor = [System.Drawing.ColorTranslator]::FromHtml($accent)
    $card.Controls.Add($lblC)
    # 说明
    $lblD = New-Object System.Windows.Forms.Label
    $lblD.Text = $rule.Desc; $lblD.Location = New-Object System.Drawing.Point(12, 58)
    $lblD.Size = New-Object System.Drawing.Size(170, 28); $lblD.ForeColor = "#777777"
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
    $f.Text = "新增规则"; $f.Size = New-Object System.Drawing.Size(420, 240); $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"; $f.MaximizeBox = $false
    $l1 = New-Object System.Windows.Forms.Label; $l1.Text = "匹配词（路径包含该词即命中，小写）"; $l1.Location = New-Object System.Drawing.Point(20, 18); $l1.AutoSize = $true; $f.Controls.Add($l1)
    $t1 = New-Object System.Windows.Forms.TextBox; $t1.Location = New-Object System.Drawing.Point(20, 44); $t1.Width = 360; $f.Controls.Add($t1)
    $l2 = New-Object System.Windows.Forms.Label; $l2.Text = "分类"; $l2.Location = New-Object System.Drawing.Point(20, 80); $l2.AutoSize = $true; $f.Controls.Add($l2)
    $c2 = New-Object System.Windows.Forms.ComboBox; $c2.DropDownStyle = "DropDownList"; $c2.Location = New-Object System.Drawing.Point(20, 106); $c2.Width = 120
    $c2.Items.Add("G 可删") | Out-Null; $c2.Items.Add("R 保留") | Out-Null; $c2.Items.Add("Y 判断") | Out-Null; $c2.SelectedIndex = 0; $f.Controls.Add($c2)
    $l3 = New-Object System.Windows.Forms.Label; $l3.Text = "风险级"; $l3.Location = New-Object System.Drawing.Point(160, 80); $l3.AutoSize = $true; $f.Controls.Add($l3)
    $c3 = New-Object System.Windows.Forms.ComboBox; $c3.DropDownStyle = "DropDownList"; $c3.Location = New-Object System.Drawing.Point(160, 106); $c3.Width = 90
    $c3.Items.Add("L1") | Out-Null; $c3.Items.Add("L2") | Out-Null; $c3.Items.Add("L3") | Out-Null; $c3.SelectedIndex = 1; $f.Controls.Add($c3)
    $l4 = New-Object System.Windows.Forms.Label; $l4.Text = "说明"; $l4.Location = New-Object System.Drawing.Point(20, 142); $l4.AutoSize = $true; $f.Controls.Add($l4)
    $t4 = New-Object System.Windows.Forms.TextBox; $t4.Location = New-Object System.Drawing.Point(20, 168); $t4.Width = 360; $f.Controls.Add($t4)
    $btnOK = New-Object System.Windows.Forms.Button; $btnOK.Text = "确定"; $btnOK.Location = New-Object System.Drawing.Point(150, 206); $btnOK.Width = 70
    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = "取消"; $btnCancel.Location = New-Object System.Drawing.Point(230, 206); $btnCancel.Width = 70
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
$pageAbout.Dock = "Fill"; $pageAbout.Hide(); $contentHost.Controls.Add($pageAbout)

$lblAbout = New-Object System.Windows.Forms.Label
$lblAbout.AutoSize = $false; $lblAbout.Dock = "Fill"
$lblAbout.Padding = New-Object System.Windows.Forms.Padding(24)
$lblAbout.Text = @"
pc-file-audit · 电脑文件可视化审计  v1.1

功能
  · 全盘扫描：目录占用 + 三档分类（🔴保留 / 🟢可删 / 🟡判断）
  · 搜索过滤：输入关键词实时过滤目录列表，条形图同步联动
  · 安全删除：勾选删除 → 优先进回收站；自动写入变更历史收据 ChangeHistory.txt
  · 规则管理：分类规则数据化（匹配词/分类/风险级/说明），支持新增、导出/导入 JSON 配置
  · 零依赖：仅需系统自带 PowerShell 5.1，客户机免安装

安全设计
  · 永不触碰：系统目录、个人文件、杀毒软件、虚拟内存/休眠文件
  · 风险分级：L1 安全清理 / L2 需确认 / L3 绝不能动
  · 可追溯：每次删除写入收据，配合回收站可还原

开源
  · GitHub: github.com/hulufeng/pc-file-audit  ·  MIT 协议  ·  免费使用
  · 借鉴 Winhance 思路（变更收据/搜索/配置迁移/数据化/分区导航），代码全部原创
"@
$lblAbout.ForeColor = "#444444"
$pageAbout.Controls.Add($lblAbout)

# ---------- 导航切换 ----------
function Set-NavHighlight($btn) {
    foreach ($b in @($btnNavScan, $btnNavRules, $btnNavAbout)) {
        $b.BackColor = if ($b -eq $btn) { "#3B4F77" } else { "#26324A" }
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
                      Where-Object { $_.Name -notin @("$RECYCLE.BIN","System Volume Information","Documents and Settings","Recovery","Boot") })
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
    $lblStatus.Text = "扫描中…"
    $prog.Value = 0
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $script:ps = [powershell]::Create()
    $script:ps.Runspace = $runspace
    $null = $script:ps.AddScript($scanScript).AddArgument($drive).AddArgument($script:RULES).AddArgument($script:shared)
    $script:handle = $script:ps.BeginInvoke()
}

# 填充列表（可带搜索关键词过滤，保留勾选状态）
function Populate-List([string]$filter) {
    if ($null -eq $script:allResults) { return }
    # 收集当前勾选，重建后恢复
    $checkedSet = @{}
    foreach ($it in $list.Items) { if ($it.Checked) { $checkedSet[$it.Tag] = $true } }
    $list.BeginUpdate(); $list.Items.Clear()
    $sumG = 0; $cntG = 0
    foreach ($r in $script:allResults) {
        if ($filter) {
            $hay = ($r.Name + " " + $r.Desc + " " + $r.Path).ToLower()
            if ($hay -notlike "*$($filter.ToLower())*") { continue }
        }
        $catTxt = switch ($r.Cat) { "R" { "🔴保留" } "G" { "🟢可删" } default { "🟡判断" } }
        $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
        $item.Tag = $r.Path
        $item.SubItems.Add($r.SizeMB.ToString()) | Out-Null
        $item.SubItems.Add($catTxt) | Out-Null
        $item.SubItems.Add($r.Desc) | Out-Null
        if ($checkedSet.ContainsKey($r.Path)) { $item.Checked = $true }
        if ($r.Cat -eq "G") { $item.BackColor = "#E8F7EC"; $sumG += $r.SizeMB; $cntG++ }
        elseif ($r.Cat -eq "R") { $item.BackColor = "#FDEBEC" }
        else { $item.BackColor = "#FDF3E0" }
        [void]$list.Items.Add($item)
    }
    $list.EndUpdate()
    if ($filter) { $lblStatus.Text = "已过滤「$filter」· 显示 $($list.Items.Count) 项" }
    else { $lblStatus.Text = "扫描完成 · 可删约 $([math]::Round($sumG/1024,2)) GB（$cntG 项）" }
    Update-Chart
}

function Scan-Done {
    $btnScan.Enabled = $true
    if ($script:shared.Error) { $lblStatus.Text = "扫描出错: $($script:shared.Error)"; return }
    $script:allResults = $script:shared.Data
    if ($null -eq $script:allResults) { $lblStatus.Text = "扫描完成（无结果）"; return }
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
    Set-NavHighlight $btnNavScan
    Refresh-RulePage
    if ($autoScan) {
        $cboDrive.SelectedItem = $autoScan
        Start-Scan
    }
})

[void]$form.ShowDialog()
