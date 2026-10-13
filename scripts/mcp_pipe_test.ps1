# mcp_pipe_test.ps1 — 管道批量测试 MCP 服务器全协议（不扫全盘，快速项）
$req = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_category","arguments":{"path":"C:\\Windows"}}}',
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_category","arguments":{"path":"C:\\Windows\\Temp"}}}',
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"delete_to_recycle","arguments":{"paths":["D:\\xxx"]}}}',
    '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"list_rules","arguments":{}}}',
    '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"change_history","arguments":{}}}',
    '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"search_files","arguments":{"drive":"C:","keyword":"log","min_mb":100}}}',
    '{"jsonrpc":"2.0","id":9,"method":"ping","params":{}}'
)
$req | powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Doubao\new-chat-2\qingpanxia\qingpanxia-mcp.ps1"
