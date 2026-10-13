# mcp_client_test.ps1 — 模拟 MCP 客户端测试 pc-file-audit-mcp.ps1（stdio 协议全流程）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File mcp_client_test.ps1
$server = "D:\Doubao\new-chat-2\pc-file-audit\pc-file-audit-mcp.ps1"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell"
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$server`""
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
$psi.StandardInputEncoding = New-Object System.Text.UTF8Encoding($false)
$p = [System.Diagnostics.Process]::Start($psi)

function Send([string]$json, [int]$waitMs = 1000) {
    $p.StandardInput.WriteLine($json)
    $p.StandardInput.Flush()
    Start-Sleep -Milliseconds $waitMs
    return $p.StandardOutput.ReadLine()
}

"===== 1. initialize ====="
$r = Send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
"init resp: $r"

"`n===== 2. tools/list ====="
$r = Send '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' 1500
"tools resp (first 1000 chars):"
$r.Substring(0, [Math]::Min(1000, $r.Length))

"`n===== 3. get_category C:\Windows ====="
$r = Send '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_category","arguments":{"path":"C:\\Windows"}}}'
"resp: $r"

"`n===== 4. get_category C:\Windows\Temp ====="
$r = Send '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_category","arguments":{"path":"C:\\Windows\\Temp"}}}'
"resp: $r"

"`n===== 5. delete_to_recycle WITHOUT confirm (安全护栏应拦截) ====="
$r = Send '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"delete_to_recycle","arguments":{"paths":["D:\\xxx"]}}}'
"resp: $r"

"`n===== 6. list_rules ====="
$r = Send '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"list_rules","arguments":{}}}' 1500
"resp (first 600 chars): $($r.Substring(0, [Math]::Min(600, $r.Length)))"

"`n===== 7. change_history ====="
$r = Send '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"change_history","arguments":{}}}'
"resp: $r"

"`n===== 8. search_files D: keyword=test min=50 ====="
$r = Send '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"search_files","arguments":{"drive":"D:","keyword":"test","min_mb":50}}}' 3000
"resp (first 500 chars): $($r.Substring(0, [Math]::Min(500, $r.Length)))"

"`n===== 9. scan_disk D: (全盘扫描，较慢) ====="
$r = Send '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"scan_disk","arguments":{"drive":"D:"}}}' 15000
"scan resp (first 800 chars): $($r.Substring(0, [Math]::Min(800, $r.Length)))"

"`n===== 10. ping ====="
$r = Send '{"jsonrpc":"2.0","id":10,"method":"ping","params":{}}'
"resp: $r"

$p.Kill()
"`n===== DONE ====="
