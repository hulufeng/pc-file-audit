---
name: pc-file-audit
description: 电脑全盘文件功能审计与清理决策。当用户要求"分析电脑/磁盘上的所有文件是什么""看下这些文件夹是干什么的、还需要吗""清理空文件夹/残留目录""生成文件清理判断清单"时使用。覆盖 Windows 本地电脑：扫描目录占用 → 识别每个文件夹功能（软件/系统/个人数据/缓存残留）→ 三档分类（必须保留/明确可删/用户判断）→ 用户决策后执行清理（白名单+进回收站）→ 输出汇报与文档。
---

# PC 文件审计（pc-file-audit）

## 概述

对本地 Windows 电脑做"每个文件夹是什么、多大、能不能删"的完整审计，产出让用户逐项拍板的判断清单，并在用户确认后安全清理。核心原则：**只报告不越权**——识别功能、给出三档分类，删除前必须用户点名；宁可漏删不可误删个人文件。

## 核心流程

1. **扫描（只读）**：运行 `scripts/scan_dirs.ps1 -Drive D`（可多次调用扫多个盘），得到一级目录大小、二级目录大小（>5MB）、大文件（>100MB）
2. **识别功能**：对照 `references/dir-guide.md` 的目录功能对照表，标注每个目录"是什么软件/系统/数据/残留"
3. **三档分类**：
   - 🔴 **必须保留**：在用软件、驱动、系统目录、个人文件、pagefile
   - 🟢 **明确可删**：已卸载软件残留、空目录、缓存壳、过期安装包（无需再确认内容，但删除仍等用户点名）
   - 🟡 **用户判断**：可能不常用的软件/数据（列出判断点让用户决定）
4. **用户决策**：把三档清单给用户，等明确指令（"第二档删""这些都保留"）
5. **执行清理**：按用户点名删除；能用回收站就进回收站（`[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFileSystemEntry($p,'OnlyErrorDialogs','SendToRecycleBin')`，失败再 `Remove-Item -Recurse -Force` 兜底）；跳过 `$RECYCLE.BIN`、`System Volume Information`、`pagefile.sys`、`swapfile.sys`、`hiberfil.sys`、`C:\Windows` 系统目录
6. **汇报 + 文档**：前后空间对比、删除明细；用户要求记录时生成 Markdown 分析文档
7. **迭代复盘**：按下方"自我迭代协议"执行，把本次新经验沉淀回本 Skill

## 安全规则（硬约束）

- 空目录判定必须含隐藏文件：`@(Get-ChildItem $d -Force).Count -eq 0` 才算真空
- 删除前先列出白名单根目录，绝不删：用户个人目录（桌面/文档/下载/图片/视频）、`Roaming\Microsoft`（系统密钥/证书结构）、任何含个人数据的目录
- 残留目录删除前展开确认内容（如 `Roaming\<GUID>` 要先看是哪个软件）
- 空目录/残留删除后，运行中的软件可能**立即重建**——剩余的新空目录属正常现象，不要反复删
- 汇报模板：三档表 + 释放空间 + 剩余保留项；实际删除过文件时附回收站链接 `[打开回收站](trash://open)`

## 深度扫描检查清单（GitHub 工具调研借鉴，2026-10-11 加入）

基础扫描（scan_dirs.ps1）覆盖日常目录后，**用户质疑"没扫全面"或要求彻底分析时**，按此清单补做深层检查（全部只读，借鉴 WinDirStat/WizTree/CleanOS/Czkawka 等开源工具思路）：

1. **系统级文件**：`vssadmin list shadowstorage`（还原点/卷影副本占用，需管理员）、`powercfg /a`（休眠是否启用）+ `C:\hiberfil.sys`（休眠文件=内存大小）、`DISM /Online /Cleanup-Image /AnalyzeComponentStore`（WinSxS 组件存储占用，需管理员）
2. **系统网络缓存**：`%LOCALAPPDATA%\Microsoft\Windows\INetCache`（IE/系统网络缓存，CleanOS 覆盖项）
3. **开发者缓存**：`%APPDATA%\npm-cache`、`%LOCALAPPDATA%\pip\cache`、`%LOCALAPPDATA%\NuGet\v3-cache`、`%USERPROFILE%\.gradle\caches`、`%USERPROFILE%\.m2\repository`（CleanOS 覆盖项）
4. **重复文件**：同名同大小（先按 Name+Length 分组，>40MB 以上才查，避免全盘哈希太慢）；真正去重要 `Get-FileHash` 比对（Czkawka/UltraTree 思路）
5. **浏览器旧版本残留**：`<浏览器>\Application\<版本号>` 目录——**删除前必须先验证该版本是否正在使用**（`(Get-Item msedge.exe).VersionInfo.ProductVersion` + 注册表 `HKLM:\SOFTWARE\...\EdgeUpdate\Clients\{GUID}\pv`），只有当前版本 != 目录版本时才可删
6. **磁盘根目录**：盘根目录常藏卸载残留（如 QQ 管家 QMMemScanner.exe 等 15 个文件），逐文件核对
7. **回收站复核**：Shell COM 计数可能为 0 但实际占空间（文件级扫描能看见）
8. **版本残留扫描**（2026-10-11 实战新增，可清量大头）：
   - 驱动安装包：`C:\Program Files\<厂商>\Install`（如 CONEXANT\Install，cab/msi 安装缓存）——驱动装完即删，实测可清 292MB
   - 浏览器旧版本：`<浏览器>\Application\<版本号>` 多版本共存时旧版可删（实测 QQ浏览器 12.2→20.1 清 271MB）
   - 组件池多版本：`<软件>\addons\pool\win-i386\<组件名>_<版本号>`（WPS 在线组件）——正则 `^(.*)_(\d+\.\d+\.\d+\.\d+)$` 分组，保留每组件最高版本删其余，实测 152 目录清 476MB
   - 搜狗组件：`SogouInput\Components\<组件>\<版本号>` 旧版可删
   - 规则：任何"组件名_版本号"目录多版本共存 = 旧版本残留候选；唯一版本 = 在用版本（勿删）

删除旧版本残留/重复文件的建议：旧版本目录删前改名（`Rename-Item xxx.old`）确认系统正常 1-2 天后再删，天然可回滚。

## 常见坑（实战验证）

- **PowerShell 5.1**：不要用 `&&`（用 `;`）；正则里 `\(` 会报"格式不正确的 \p{X} 字符转义"，用 `-like` 代替
- **SendToRecycleBin 可能失败**（权限/占用），必须 try/catch 兜底 `Remove-Item`；失败分支的删除不进回收站，汇报时如实说明
- **服务修复要用 SCM 正规方式**：直接改注册表 Start 值后 SCM 缓存仍是旧状态（报 1058），必须 `sc.exe config <服务> start= auto` 刷新（见 `references/fixes.md`）
- **清空回收站一次可能清不净**（遗留 ~600MB），清后重测回收站大小，非 0 则用 `Remove-Item` 补删 `D:\$RECYCLE.BIN\*`
- **`*.leveldb\000003.log` 是数据库 WAL 不是日志**：路径含 `leveldb`/`IndexedDB` 的 .log 是 Chromium 系应用数据库组件，永不删；真日志在 `sdk_storage\log\`、`logs\`、`*.Log`
- **"唯一版本目录"不一定是残留**：Edge/Chrome 的 `Application\<版本>` 目录是唯一版本时就是正在用的版本（老机器 Edge 可能长期停在旧版），删除前必验证当前版本
- **清理 temp 加时间过滤更稳**（CleanOS 经验）：只删 `LastWriteTime` 1 天前的临时文件，避免误删正在使用的

## 用户决策记录（decisions.md）

用户对每个文件的删/留决定写入 `references/decisions.md`（新条目在上）。后续审计同类文件时**直接按已记录决策执行**（用户可随时推翻），这是本 Skill 的"决策记忆"——复用规则：路径特征匹配（如 `QM*`/`beacon*` = QQ管家残留→删）、软件判断（展视/Steam/腾讯视频/微信开发者工具→用户已确认不用）、系统必需（PAGEFILE/swapfile/BCD.LOG/leveldb→永不删）。

## 自我迭代协议（变聪明机制）

本 Skill 必须**每次使用后执行复盘**，把新经验沉淀回来，越用越准：

1. **复盘三问**（任务收尾时逐条自答）：
   - 遇到新坑/新报错/新残留类型/新目录了吗？→ 追加到 `references/experience-log.md`
   - 有更高效的命令、更稳的流程改进吗？→ 追加到 experience-log 的"流程改进"区
   - 目录对照表有遗漏或可补充的吗？→ 直接补进 `references/dir-guide.md`

2. **写入经验库**：在 `references/experience-log.md` 顶部追加条目，格式：
   ```
   ### [YYYY-MM-DD] 一句话标题
   - 场景：什么任务/环境
   - 现象：看到什么
   - 根因：为什么
   - 解法：怎么解决（可执行的命令/步骤）
   - 状态：待合并 / 已合并
   ```

3. **合并成熟经验**（保持主文档精炼，防止越用越臃肿）：
   - 某条经验第二次复现（同类问题再次遇到）→ 状态改为"已合并"，内容提升进 `fixes.md` 或 `dir-guide.md`
   - 经验库超过 30 条 → 清理：低频/过时的归档删除，高频的合入主文档
   - 合并时只在主文档写入"可执行结论 + 一句根因"，把详细排查过程留在 experience-log
   - 合并完成后在主文档对应条目加注释来源（如"经验源自 experience-log ### 2026-10-11"）

4. **纪律**（防止"假聪明"）：
   - 只记**可复用的事实/命令/坑**，不记一次性任务细节，不注水
   - 主文档（SKILL.md）永远保持 <500 行；细节全在 references
   - 不新建多余的顶层文档（README/CHANGELOG 等）；一切沉淀进现有结构
   - 每完成一次"合并"，在 experience-log 里把对应条目标注 [已合并]，保持经验库可追溯

## 可视化窗口（GUI 模式，2026-10-12 加入）

用户要求"扫客户电脑后做成可视化窗口"或需要给非技术用户自助清理时，交付 `pc-file-audit-gui.ps1`（PowerShell + WinForms，**零依赖**——客户机只需 Windows 自带 PowerShell 5.1，无需装 Python/任何库）。

用法（v1.1，2026-10-13 全面升级，借鉴 Winhance 思路原创实现）：
1. 复制 `pc-file-audit-gui.ps1` 到客户电脑，右键 → 使用 PowerShell 运行（或双击）
2. **左侧导航三页**：扫描 / 规则 / 关于（借鉴分区导航）
3. 扫描页：选择盘符 → 开始扫描 → 表格列出每个目录（名称/大小/🔴保留/🟢可删/🟡判断/说明）+ 右侧条形图 Top15
4. **搜索过滤**：顶部搜索框实时过滤目录列表（400ms 防抖），条形图随过滤联动
5. 勾选要删项（🟢 默认勾选）→ 删除按钮 → 优先进回收站（SHFileOperationW），失败才永久删
6. **变更历史收据**：每次删除自动追加写入脚本同目录 `ChangeHistory.txt`（时间戳标题 + 每项路径/大小 + UTF-8 BOM + CRLF）——配合回收站实现"可追溯、可回滚"；点"查看删除记录"按钮用记事本打开
7. **规则页**：分类规则数据化展示（匹配词/分类/风险级/说明卡片流），支持"＋新增规则"；**导出/导入配置**为 JSON（`ConvertTo-Json`，UTF-8 BOM），换机/客户机一键复用清理规则

技术要点：
- **PowerShell 5.1 后台扫描必须用独立 Runspace**（`[runspacefactory]::CreateRunspace()` + `[powershell]::Create()`），不能用 BackgroundWorker 事件脚本块（后台线程无运行空间，调用函数报"此线程中没有可用于运行脚本的运行空间"）
- 进度刷新：共享 `[hashtable]::Synchronized(@{...})` 由后台写入，UI 用 `System.Windows.Forms.Timer`（300ms）轮询读取
- **分类规则已数据化**：`$RULES` 结构化数组（Pattern/Cat/Desc/Risk），内置约 38 条；匹配顺序固定**先 G（可删）再 R（保留）**，否则 `\windows` 会把 `Windows\Temp` 等缓存标成保留；风险分级 L1 安全清理/L2 需确认/L3 绝不能动
- 搜索过滤重建列表时保留勾选状态（先收集 Checked 集合，重建后恢复）
- 脚本必须 UTF-8 BOM；`Add-Type -TypeDefinition` 内联 C# 实现回收站删除
- 验证参数：`-AutoScan D:` 启动后自动扫描指定盘，便于自动化截图验证
- 辅助实现 `pc-file-audit-gui.py`（tkinter 版）仅在系统 Python 带完整 Tcl 时可用；沙箱/精简 Python 会报 `Can't find a usable init.tcl`，优先用 .ps1 版

## MCP Server 模式（2026-10-13 加入）

用户要求"让任意 AI 客户端（Claude/Cursor/豆包等）通过 MCP 协议调用扫描/分类/删除能力"时，交付 `pc-file-audit-mcp.ps1`（**PowerShell 原生实现 MCP stdio 协议，零依赖**——客户机只需 Windows 自带 PowerShell 5.1，无需 Python/uv/任何库）。借鉴 Windows-MCP（CursorTouch/Windows-MCP，MIT）"能力即工具"思想，代码全部原创。

启动：`powershell -NoProfile -ExecutionPolicy Bypass -File pc-file-audit-mcp.ps1`（MCP 客户端配置为本地 stdio server 即可）

**7 个工具**（协议：newline-delimited JSON-RPC 2.0）：
- `scan_disk(drive)` 全盘扫描一级/二级目录 → 名称/大小MB/分类/风险级/说明
- `dir_size(path)` 目录占用
- `get_category(path)` 三档分类判断
- `search_files(drive, keyword, min_mb)` 大文件搜索
- `list_rules()` 规则清单（38 条，与 GUI 同源数据化）
- `delete_to_recycle(paths, confirm)` 安全删除
- `change_history()` 变更收据读取

**安全护栏（默认强制，借鉴 Windows-MCP 的安全配置思想但反过来默认全关风险面）**：
- 扫描/查询工具全部只读
- `delete_to_recycle` 必须携带 `confirm=YES` 才执行（无确认参数即拦截）
- 删除只进回收站（SHFileOperationW，失败 Remove-Item 兜底）+ 写 `ChangeHistory.txt` 变更收据
- 不提供 PowerShell/Registry 等全系统高危工具（Windows-MCP 默认全开，我们默认不开放）

技术要点（实测验证）：
- **MCP stdio = newline-delimited JSON-RPC**，每行一条消息；`[Console]::In.ReadLine()` 循环读、`[Console]::Out.WriteLine()` + `Flush()` 写（必须绕开 PS 管道，否则污染协议）
- `[Console]::OutputEncoding = UTF8 无 BOM`；脚本文件本身 UTF-8 BOM
- 测试方式：**管道批量喂 JSON 最稳**（`$req | powershell -File server.ps1`，服务器逐行响应）——不要用 ProcessStartInfo 重定向管道交互（PS 5.1 时序/编码坑多）
- **坑：PS 双引号字符串里 `$RECYCLE.BIN`/`$recycle.bin` 会被当变量展开成 `.BIN`/`.bin`**——含 `$` 的模式必须用单引号
- JSON Schema 工具描述里的 `"` 必须避免（PS 双引号内 `\"` 不转义），写 `confirm=YES` 不带引号
- `change_history` 读文件用 `[IO.File]::ReadAllText`（`Get-Content -Raw` 会被 ConvertTo-Json 序列化成含 PSPath 的对象）
- 分类规则复用 GUI 的 `$RULES` 数据结构（Pattern/Cat/Risk/Desc），保证 GUI 与 MCP 判定一致

## 资源

- `scripts/scan_dirs.ps1` —— 目录占用扫描（一级/二级/大文件），只读
- `pc-file-audit-gui.ps1` —— **可视化窗口 GUI（零依赖，客户电脑直接可跑）**
- `pc-file-audit-mcp.ps1` —— **MCP Server（零依赖，任意 AI 客户端可接入）**
- `references/dir-guide.md` —— Windows 常见目录功能对照表 + 分类规则
- `references/fixes.md` —— 实战修复案例（服务文件缺失、SCM 缓存、卸载残留、回收站清不净）
- `references/experience-log.md` —— **经验库**：每次任务的复盘沉淀，是自我迭代的载体
