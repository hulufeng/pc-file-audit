# mcp_clean2.ps1 — 用 MCP 补清剩余豆包日志（第二次实战）
$logDir = "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log"
$remaining = @(Get-ChildItem $logDir -Filter "saman_*.log" -EA SilentlyContinue)
"剩余日志: $($remaining.Count) 个"
$pathsJson = ($remaining | ForEach-Object { '"' + ($_.FullName -replace '\\', '\\\\') + '"' }) -join ','
$req = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    ('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"delete_to_recycle","arguments":{"paths":[' + $pathsJson + '],"confirm":"YES"}}}'),
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"change_history","arguments":{}}}'
)
$resp = $req | powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Doubao\new-chat-2\qingpanxia\scripts\qingpanxia-mcp.ps1"
$resp | ForEach-Object { $_.Substring(0, [Math]::Min(300, $_.Length)) }
"`n--- 再次检查剩余 ---"
$after = @(Get-ChildItem $logDir -Filter "saman_*.log" -EA SilentlyContinue)
if ($after.Count -eq 0) { "全部清理完成!" } else {
    $sz = ($after | Measure-Object Length -Sum).Sum / 1MB
    "仍剩 $($after.Count) 个, 共 $([math]::Round($sz,1)) MB（被豆包进程占用，退出豆包后可清）"
}
