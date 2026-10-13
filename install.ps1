# ============================================================
# pc-file-audit 一键安装器（给别人用，双击即用）
# 用法: 右键"使用 PowerShell 运行" 或 powershell -File install.ps1
# 功能: ① GUI 直用 ② 装进 AI 助手(Skill) ③ MCP AI 直连(自动生成配置)
# ============================================================
$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Banner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   pc-file-audit · PC 文件审计与清理（免费开源）║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Install-Skill {
    # 豆包技能目录真实位置探测（不同版本路径不同，取第一个存在的）
    $doubaoCandidates = @(
        "$env:LOCALAPPDATA\Doubao\User Data\Default\.doubao\agent_mode\workspace\.user_skills\pc-file-audit",
        "$env:USERPROFILE\.doubao\agent_mode\workspace\.user_skills\pc-file-audit"
    )
    $doubao = $doubaoCandidates | Where-Object { Test-Path (Split-Path $_ -Parent) } | Select-Object -First 1
    $claude = "$env:USERPROFILE\.claude\skills\pc-file-audit"
    $targets = @(
        @{ Name="豆包(Doubao)"; Path=$doubao },
        @{ Name="Claude";       Path=$claude }
    )
    $installed = $false
    foreach ($t in $targets) {
        if ($t.Path -and (Test-Path (Split-Path $t.Path -Parent))) {
            New-Item -ItemType Directory -Path $t.Path -Force | Out-Null
            Copy-Item "$here\SKILL.md" $t.Path -Force
            Copy-Item "$here\references" "$($t.Path)\references" -Recurse -Force
            Copy-Item "$here\scripts" "$($t.Path)\scripts" -Recurse -Force
            Write-Host "  ✓ 已安装到 $($t.Name) 技能目录: $($t.Path)" -ForegroundColor Green
            $installed = $true
        }
    }
    if (-not $installed) {
        New-Item -ItemType Directory -Path $doubao -Force | Out-Null
        Copy-Item "$here\SKILL.md" $doubao -Force
        Copy-Item "$here\references" "$doubao\references" -Recurse -Force
        Copy-Item "$here\scripts" "$doubao\scripts" -Recurse -Force
        Write-Host "  ✓ 已安装到豆包技能目录: $doubao" -ForegroundColor Green
        Write-Host "  （如果以后用 Claude，把文件夹复制到 ~/.claude/skills/ 即可）"
    }
}

function Add-McpConfig($client, $cfgPath, $scriptBlock) {
    if (Test-Path $cfgPath) {
        Write-Host "  ✓ 检测到 $client，正在写入配置..." -ForegroundColor Green
        try { & $scriptBlock } catch { Write-Host "  ✗ 写入失败: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

function Install-Mcp {
    $server = Join-Path $here "scripts\pc-file-audit-mcp.ps1"
    Write-Host "  MCP Server 位置: $server" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  检测本机已安装的 AI 客户端..." -ForegroundColor Cyan

    # Claude Desktop
    $claudeCfg = "$env:APPDATA\Claude\claude_desktop_config.json"
    if (Test-Path $claudeCfg) {
        Write-Host "  ✓ Claude Desktop 已安装，自动写入配置" -ForegroundColor Green
        try {
            $cfg = Get-Content $claudeCfg -Raw -Encoding UTF8 | ConvertFrom-Json
            $cfg.mcpServers | Add-Member -NotePropertyName "pc-file-audit" -NotePropertyValue ([pscustomobject]@{
                command = "powershell"
                args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$server)
            }) -Force
            $cfg | ConvertTo-Json -Depth 8 | Out-File $claudeCfg -Encoding UTF8
            Write-Host "    → 已写入，重启 Claude Desktop 生效" -ForegroundColor Green
        } catch { Write-Host "  ✗ 写入失败: $($_.Exception.Message)" -ForegroundColor Red }
    }

    # Cursor
    $cursorCfg = "$env:USERPROFILE\.cursor\mcp.json"
    if (Test-Path $cursorCfg) {
        Write-Host "  ✓ Cursor 已安装，自动写入配置" -ForegroundColor Green
        try {
            $cfg = Get-Content $cursorCfg -Raw -Encoding UTF8 | ConvertFrom-Json
            $cfg.mcpServers | Add-Member -NotePropertyName "pc-file-audit" -NotePropertyValue ([pscustomobject]@{
                command = "powershell"
                args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$server)
            }) -Force
            $cfg | ConvertTo-Json -Depth 8 | Out-File $cursorCfg -Encoding UTF8
            Write-Host "    → 已写入，重启 Cursor 生效" -ForegroundColor Green
        } catch { Write-Host "  ✗ 写入失败: $($_.Exception.Message)" -ForegroundColor Red }
    }

    # Gemini CLI
    $geminiCfg = "$env:USERPROFILE\.gemini\settings.json"
    if (Test-Path $geminiCfg) {
        Write-Host "  ✓ Gemini CLI 已安装，自动写入配置" -ForegroundColor Green
        try {
            $cfg = Get-Content $geminiCfg -Raw -Encoding UTF8 | ConvertFrom-Json
            $cfg.mcpServers | Add-Member -NotePropertyName "pc-file-audit" -NotePropertyValue ([pscustomobject]@{
                command = "powershell"
                args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$server)
            }) -Force
            $cfg | ConvertTo-Json -Depth 8 | Out-File $geminiCfg -Encoding UTF8
            Write-Host "    → 已写入，重启 Gemini CLI 生效" -ForegroundColor Green
        } catch { Write-Host "  ✗ 写入失败: $($_.Exception.Message)" -ForegroundColor Red }
    }

    # 未检测到任何客户端时，打印通用配置
    if (-not (Test-Path $claudeCfg) -and -not (Test-Path $cursorCfg) -and -not (Test-Path $geminiCfg)) {
        Write-Host "  （未检测到已安装的 MCP 客户端）" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  通用接入配置（装好任一款支持 MCP 的 AI 客户端后，粘贴这段即可）：" -ForegroundColor Cyan
        Write-Host ""
        Write-Host '  { "mcpServers": { "pc-file-audit": { "command": "powershell", "args": ["-NoProfile","-ExecutionPolicy","Bypass","-File","'$server'"] } } }' -ForegroundColor White
        Write-Host ""
        Write-Host "  支持: Claude Desktop / Cursor / Gemini CLI / Qwen Code / Codex / Cherry Studio / ChatWise ..." -ForegroundColor Cyan
    }
}

function Show-Usage {
    Write-Host ""
    Write-Host "  使用方式：" -ForegroundColor Cyan
    Write-Host "    1. GUI 图形界面（推荐给普通用户）: 双击 scripts\pc-file-audit-gui.ps1"
    Write-Host "    2. AI 助手技能（豆包/Claude）: 复制 pc-file-audit 文件夹到技能目录"
    Write-Host "    3. MCP AI 直连（极客）: 让 AI 直接调用扫描/删除能力"
    Write-Host ""
    Write-Host "  选择安装方式 (1=全部安装 2=只装AI助手技能 3=只配MCP 4=只看说明): " -NoNewline -ForegroundColor Cyan
    $choice = Read-Host
    switch ($choice) {
        "1" { Install-Skill; Install-Mcp }
        "2" { Install-Skill }
        "3" { Install-Mcp }
        default { Write-Host "  （未安装，只看说明。GUI 直接双击 scripts\pc-file-audit-gui.ps1 即可用）" -ForegroundColor Yellow }
    }
}

Show-Banner
Show-Usage
Write-Host ""
Write-Host "  安装完成！GUI 直接双击 scripts\pc-file-audit-gui.ps1 即可使用。" -ForegroundColor Green
Write-Host ""
