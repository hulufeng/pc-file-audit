# mcp_scan_test.ps1 — 测 scan_disk + 修复后的 change_history
$req = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"change_history","arguments":{}}}',
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"scan_disk","arguments":{"drive":"C:"}}}'
)
$req | powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Doubao\new-chat-2\qingpanxia\qingpanxia-mcp.ps1"
