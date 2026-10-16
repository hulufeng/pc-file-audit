# mcp_clean_logs.ps1 — 用 MCP delete_to_recycle 清理豆包日志（实战演练）
$logs = @(
    "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log\saman_2026.1013.0.log",
    "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log\saman_2026.1011.2.log",
    "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log\saman_2026.1011.1.log",
    "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log\saman_2026.1013.1.log",
    "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log\saman_2026.1012.0.log",
    "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log\saman_2026.1011.3.log",
    "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log\saman_2026.1010.2.log"
)
"待清理日志文件数: $($logs.Count)"
$pathsJson = ($logs | ForEach-Object { '"' + ($_ -replace '\\', '\\\\') + '"' }) -join ','
$req = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    ('{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"delete_to_recycle","arguments":{"paths":[' + $pathsJson + '],"confirm":"YES"}}}'),
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"change_history","arguments":{}}}'
)
$resp = $req | powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Doubao\new-chat-2\qingpanxia\scripts\qingpanxia-mcp.ps1"
"--- MCP 响应 ---"
$resp | ForEach-Object { $_.Substring(0, [Math]::Min(500, $_.Length)) }

"`n--- 删除后剩余日志 ---"
$remaining = @(Get-ChildItem "C:\Users\Administrator\AppData\Local\Doubao\User Data\sdk_storage\log" -Filter "saman_*.log" -EA SilentlyContinue)
if ($remaining.Count -eq 0) { "全部已清理!" } else {
    $sz = ($remaining | Measure-Object Length -Sum).Sum / 1MB
    "剩余 $($remaining.Count) 个, 共 $([math]::Round($sz,1)) MB"
    $remaining | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}} | Format-Table -AutoSize
}
