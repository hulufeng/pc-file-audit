# pc-file-audit MCP Server —— 电脑文件审计能力开放给任意 AI 客户端（PowerShell 原生，零依赖）
# =============================================================================
# MCP(Model Context Protocol) stdio 传输：newline-delimited JSON-RPC 2.0
# 任何支持 MCP 的客户端（Claude/Cursor/豆包等）可配置本脚本为本地 MCP Server
# 借鉴 Windows-MCP 的"能力即工具"思想，代码全部原创；安全护栏默认强制：
#   - 所有扫描/查询工具只读
#   - delete_to_recycle 必须携带 confirm="YES" 才执行，且只进回收站 + 写变更收据
# 依赖：仅 Windows 自带 PowerShell 5.1（客户机免安装任何东西）
# 编码：本文件须为 UTF-8 BOM；stdout 输出 UTF-8 无 BOM JSON（MCP 协议要求）
# 启动：powershell -NoProfile -ExecutionPolicy Bypass -File pc-file-audit-mcp.ps1
# =============================================================================

$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# ---------- 分类规则（设置项数据化：Pattern / Cat / Desc / Risk） ----------
# Cat: R=必须保留  G=明确可删  Y=用户判断；Risk: L1安全清理 L2需确认 L3绝不能动
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
    @{ Pattern='$recycle.bin';            Cat="R"; Desc="回收站";                         Risk="L3" },
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

$script:historyFile = Join-Path $PSScriptRoot "ChangeHistory.txt"

# ---------- 回收站删除（SHFileOperationW，C# 内联） ----------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class McpRecycle {
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
        op.wFunc = 3; op.pFrom = path + "\0\0";
        op.fFlags = 0x40 | 0x10 | 0x4;
        return SHFileOperation(ref op) == 0;
    }
}
"@

# ---------- 核心工具函数（只读优先） ----------
function Get-Category([string]$path) {
    $low = $path.ToLower()
    foreach ($r in $script:RULES) { if ($r.Cat -eq "G" -and $low -like "*$($r.Pattern)*") { return [pscustomobject]@{ Cat="G"; Label="🟢可删"; Risk=$r.Risk; Desc=$r.Desc } } }
    foreach ($r in $script:RULES) { if ($r.Cat -eq "R" -and $low -like "*$($r.Pattern)*") { return [pscustomobject]@{ Cat="R"; Label="🔴保留"; Risk=$r.Risk; Desc=$r.Desc } } }
    return [pscustomobject]@{ Cat="Y"; Label="🟡判断"; Risk="L2"; Desc="用户判断是否继续使用" }
}

function Get-DirSizeMB([string]$path) {
    $total = 0L
    $stack = New-Object System.Collections.Stack
    $stack.Push($path)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            $di = [System.IO.DirectoryInfo]::new($dir)
            foreach ($sd in $di.EnumerateDirectories()) { $stack.Push($sd.FullName) }
            foreach ($f in $di.EnumerateFiles()) { try { $total += $f.Length } catch {} }
        } catch {}
    }
    return [math]::Round($total / 1MB, 1)
}

function Scan-Disk([string]$drive) {
    $root = $drive.TrimEnd(":\") + ":\"
    $out = New-Object System.Collections.ArrayList
    $topDirs = @(Get-ChildItem $root -Directory -Force -EA SilentlyContinue |
                  Where-Object { $_.Name -notin @('$RECYCLE.BIN',"System Volume Information","Documents and Settings","Recovery","Boot") })
    foreach ($d in $topDirs) {
        $s = Get-DirSizeMB $d.FullName
        $c = Get-Category $d.FullName
        [void]$out.Add([pscustomobject]@{ Name=$d.Name; Path=$d.FullName; SizeMB=$s; Cat=$c.Cat; Label=$c.Label; Risk=$c.Risk; Desc=$c.Desc; Level=0 })
        if ($c.Cat -eq "R") {
            Get-ChildItem $d.FullName -Directory -Force -EA SilentlyContinue | ForEach-Object {
                $c2 = Get-Category $_.FullName
                if ($c2.Cat -eq "G") {
                    $ss = Get-DirSizeMB $_.FullName
                    [void]$out.Add([pscustomobject]@{ Name="    " + $_.Name; Path=$_.FullName; SizeMB=$ss; Cat=$c2.Cat; Label=$c2.Label; Risk=$c2.Risk; Desc=$c2.Desc; Level=1 })
                }
            }
        } else {
            Get-ChildItem $d.FullName -Directory -Force -EA SilentlyContinue | ForEach-Object {
                $ss = Get-DirSizeMB $_.FullName
                if ($ss -gt 10) {
                    $c2 = Get-Category $_.FullName
                    [void]$out.Add([pscustomobject]@{ Name="    " + $_.Name; Path=$_.FullName; SizeMB=$ss; Cat=$c2.Cat; Label=$c2.Label; Risk=$c2.Risk; Desc=$c2.Desc; Level=1 })
                }
            }
        }
    }
    return $out
}

function Search-Files([string]$drive, [string]$keyword, [double]$minMB) {
    $root = $drive.TrimEnd(":\") + ":\"
    $kw = $keyword.ToLower()
    $out = New-Object System.Collections.ArrayList
    Get-ChildItem $root -Recurse -File -Force -EA SilentlyContinue |
        Where-Object { $_.Length -gt ($minMB * 1MB) -and $_.Name.ToLower() -like "*$kw*" } |
        Sort-Object Length -Descending | Select-Object -First 50 |
        ForEach-Object { [void]$out.Add([pscustomobject]@{ Name=$_.Name; Path=$_.FullName; SizeMB=[math]::Round($_.Length/1MB,1) }) }
    return $out
}

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

function Delete-ToRecycle([string[]]$paths, [string]$confirm) {
    if ($confirm -ne "YES") {
        return [pscustomobject]@{ Ok=$false; Message="安全护栏：删除必须携带 confirm=`"YES`" 参数才会执行。被删除项只会进回收站并写入变更收据。" }
    }
    $ok = 0; $rec = 0; $histLines = @()
    foreach ($p in $paths) {
        if (Test-Path $p) {
            if ([McpRecycle]::Send($p)) { $rec++ }
            else { Remove-Item $p -Recurse -Force -Confirm:$false }
            $ok++
            $sz = Get-DirSizeMB $p
            $histLines += "$p ($sz MB)"
        }
    }
    if (@($histLines).Count -gt 0) {
        Add-HistoryBatch "删除 $(@($histLines).Count) 项（$rec 项进回收站，$($ok - $rec) 项永久删除）" $histLines
    }
    return [pscustomobject]@{ Ok=$true; Deleted=$ok; ToRecycle=$rec; History=$script:historyFile }
}

# ---------- MCP 工具注册表（name -> scriptblock，参数用 params 数组） ----------
$script:TOOLS = @(
    @{
        Name = "scan_disk"
        Description = "扫描指定盘符的一级/二级目录，返回每个目录的名称、大小(MB)、分类(🔴保留/🟢可删/🟡判断)、风险级(L1/L2/L3)和说明。只读操作。"
        Properties = @{ drive = @{ type="string"; description="盘符，如 C: 或 D" } }
        Required = @("drive")
    },
    @{
        Name = "dir_size"
        Description = "计算指定目录的占用大小(MB)。只读操作。"
        Properties = @{ path = @{ type="string"; description="目录完整路径" } }
        Required = @("path")
    },
    @{
        Name = "get_category"
        Description = "判断指定路径的分类：🔴保留/🟢可删/🟡判断 + 风险级 + 说明。只读操作。"
        Properties = @{ path = @{ type="string"; description="目录或文件完整路径" } }
        Required = @("path")
    },
    @{
        Name = "search_files"
        Description = "在指定盘搜索大文件，可按文件名关键词过滤。只读操作。"
        Properties = @{
            drive = @{ type="string"; description="盘符，如 D:" }
            keyword = @{ type="string"; description="文件名包含的关键词（可选，空则全列）" }
            min_mb = @{ type="number"; description="最小文件大小(MB)，默认 100" }
        }
        Required = @("drive")
    },
    @{
        Name = "list_rules"
        Description = "列出当前分类规则（匹配词/分类/风险级/说明）。只读操作。"
        Properties = @{}
        Required = @()
    },
    @{
        Name = "delete_to_recycle"
        Description = "把指定路径移入回收站（若回收站不可用则永久删除）并写入变更收据 ChangeHistory.txt。⚠️ 安全护栏：必须传 confirm=YES 才会执行；只清理缓存/残留类，不触碰系统目录。"
        Properties = @{
            paths = @{ type="array"; items=@{ type="string" }; description="要删除的路径列表" }
            confirm = @{ type="string"; description="必须为 YES 才执行" }
        }
        Required = @("paths", "confirm")
    },
    @{
        Name = "change_history"
        Description = "读取变更历史收据（历次删除记录）。只读操作。"
        Properties = @{}
        Required = @()
    }
)

# ---------- MCP 协议分发 ----------
function Send-Json($obj) {
    $json = $obj | ConvertTo-Json -Compress -Depth 8
    [Console]::Out.WriteLine($json)
    [Console]::Out.Flush()
}

function Handle-ToolsCall($id, $paramsObj) {
    $name = $paramsObj.name
    $args = $paramsObj.arguments
    if ($null -eq $args) { $args = @{} }
    $tool = $script:TOOLS | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if (-not $tool) {
        Send-Json @{ jsonrpc="2.0"; id=$id; result=@{ content=@(@{ type="text"; text="未知工具: $name" }); isError=$true } }
        return
    }
    $text = ""
    try {
        switch ($name) {
            "scan_disk" {
                $drive = [string]$args.drive
                $res = @(Scan-Disk $drive)
                $text = ($res | ConvertTo-Json -Depth 5)
            }
            "dir_size" {
                $path = [string]$args.path
                if (-not (Test-Path $path)) { $text = "路径不存在: $path" }
                else { $text = "{`"Path`":`"$path`",`"SizeMB`":$((Get-DirSizeMB $path))}" }
            }
            "get_category" {
                $path = [string]$args.path
                if (-not (Test-Path $path)) { $text = "路径不存在: $path" }
                else { $text = (Get-Category $path | ConvertTo-Json -Compress) }
            }
            "search_files" {
                $drive = [string]$args.drive
                $kw = if ($args.keyword) { [string]$args.keyword } else { "" }
                $min = if ($args.min_mb) { [double]$args.min_mb } else { 100.0 }
                $res = @(Search-Files $drive $kw $min)
                $text = ($res | ConvertTo-Json -Depth 5)
            }
            "list_rules" {
                $text = ($script:RULES | ConvertTo-Json -Depth 5)
            }
            "delete_to_recycle" {
                $paths = @($args.paths)
                $confirm = if ($args.confirm) { [string]$args.confirm } else { "" }
                $text = (Delete-ToRecycle $paths $confirm | ConvertTo-Json -Compress)
            }
            "change_history" {
                if (Test-Path $script:historyFile) {
                    $text = [System.IO.File]::ReadAllText($script:historyFile, [System.Text.Encoding]::UTF8)
                } else {
                    $text = "暂无删除记录（ChangeHistory.txt 尚未创建）"
                }
            }
            default { $text = "未知工具: $name" }
        }
    } catch {
        Send-Json @{ jsonrpc="2.0"; id=$id; result=@{ content=@(@{ type="text"; text="工具执行出错: $($_.Exception.Message)" }); isError=$true } }
        return
    }
    Send-Json @{ jsonrpc="2.0"; id=$id; result=@{ content=@(@{ type="text"; text=$text }) } }
}

function Handle-ToolsList($id) {
    $tools = @()
    foreach ($t in $script:TOOLS) {
        $schema = @{ type="object"; properties=$t.Properties }
        if (@($t.Required).Count -gt 0) { $schema.required = $t.Required }
        $tools += @{ name=$t.Name; description=$t.Description; inputSchema=$schema }
    }
    Send-Json @{ jsonrpc="2.0"; id=$id; result=@{ tools=$tools } }
}

function Handle-Initialize($id) {
    Send-Json @{ jsonrpc="2.0"; id=$id; result=@{
        protocolVersion="2024-11-05"
        capabilities=@{ tools=@{ listChanged=$false } }
        serverInfo=@{ name="pc-file-audit-mcp"; version="1.0.0" }
    } }
}

# ---------- 主循环（stdio：逐行读 JSON-RPC，逐条回 JSON） ----------
while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    $line = $line.Trim()
    if (-not $line) { continue }
    $msg = $null
    try { $msg = $line | ConvertFrom-Json } catch { continue }
    $id = $msg.id
    $method = [string]$msg.method
    if (-not $method) { continue }
    try {
        switch ($method) {
            "initialize" { Handle-Initialize $id }
            "notifications/initialized" { }
            "ping" { Send-Json @{ jsonrpc="2.0"; id=$id; result=@{} } }
            "tools/list" { Handle-ToolsList $id }
            "tools/call" { Handle-ToolsCall $id $msg.params }
            default { Send-Json @{ jsonrpc="2.0"; id=$id; result=@{ content=@(@{ type="text"; text="不支持的方法: $method" }); isError=$true } } }
        }
    } catch {
        Send-Json @{ jsonrpc="2.0"; id=$id; result=@{ content=@(@{ type="text"; text="服务器错误: $($_.Exception.Message)" }); isError=$true } }
    }
}
