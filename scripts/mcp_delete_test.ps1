# mcp_delete_test.ps1 — 安全护栏真实删除实测
$server = "D:\Doubao\new-chat-2\pc-file-audit\pc-file-audit-mcp.ps1"
$testFile = "D:\test_mcp_delete.txt"
Set-Content $testFile "MCP delete safety test - will be moved to recycle bin" -Encoding UTF8
"1. 测试文件已创建: $(Test-Path $testFile)  size=$(Get-Item $testFile).Length"

$req = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"delete_to_recycle","arguments":{"paths":["D:\\test_mcp_delete.txt"],"confirm":"YES"}}}',
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"change_history","arguments":{}}}'
)
"`n2. 发送删除请求(confirm=YES)..."
$resp = $req | powershell -NoProfile -ExecutionPolicy Bypass -File $server
$resp | ForEach-Object { "RESP: $($_.Substring(0, [Math]::Min(400, $_.Length)))" }

"`n3. 验证文件已被移走: $(Test-Path $testFile)"
"4. 变更收据 ChangeHistory.txt:"
if (Test-Path "D:\Doubao\new-chat-2\pc-file-audit\ChangeHistory.txt") {
    Get-Content "D:\Doubao\new-chat-2\pc-file-audit\ChangeHistory.txt" -Encoding UTF8 | Select-Object -Last 5
} else { "   (未创建)" }
