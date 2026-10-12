# 经验库（experience-log）

本文件是 pc-file-audit 的自我迭代载体。每次使用 Skill 完成任务后，按 SKILL.md「自我迭代协议」在**顶部**追加新经验条目。新条目在上，旧条目在下。

---

## [2026-10-12] 可视化窗口 GUI 开发经验（PowerShell + WinForms 零依赖版）
- 场景：用户要求"扫客户电脑后做成可视化窗口"，为开源工具加 GUI 界面
- ①**沙箱 Python 无 Tcl**：`tkinter.Tk()` 报 `Can't find a usable init.tcl`——沙箱运行时 python 缺 tcl 库；客户机无 Python 依赖时 tkinter 方案不可行
- ②**改用 PowerShell + WinForms 零依赖**：`Add-Type -AssemblyName System.Windows.Forms`，Windows 5.1 自带，客户机直接可跑（双击/右键 PowerShell 运行）
- ③**BackgroundWorker 事件脚本块在后台线程无 runspace**：PowerShell 5.1 的 `$worker.Add_DoWork({...})` 里调用自定义函数报"此线程中没有可用于运行脚本的运行空间"——**必须用独立 Runspace**（`[runspacefactory]::CreateRunspace()` + `[powershell]::Create()` + `AddScript().AddArgument()` + `BeginInvoke()`）
- ④**进度/结果跨线程**：共享 `[hashtable]::Synchronized(@{Running;Progress;Current;Done;Data;Error})` 由后台写、UI `System.Windows.Forms.Timer`(300ms) 轮询读，完成时 `EndInvoke` + 填表
- ⑤**回收站删除 C# 内联**：`Add-Type -TypeDefinition` 定义 SHFILEOPSTRUCT + SHFileOperation(FO_DELETE|FOF_ALLOWUNDO|FOF_NOCONFIRMATION|FOF_SILENT)
- ⑥**验证钩子**：脚本支持 `-AutoScan D:` 参数启动即自动扫描，配合整屏截图（System.Drawing CopyFromScreen）自动化验证 GUI
- ⑦**函数名坑**：PowerShell 里自定义函数名 `Del` 与 Remove-Item 别名冲突，非交互模式报"朗读和提示功能不可用"——函数名避开内置别名
- 产物：`pc-file-audit-gui.ps1`（仓库根目录）+ `pc-file-audit-gui.py`（tkinter 备用）
- 状态：待合并（GUI 流程可复用）

---

## [2026-10-12] 技能开源发布 GitHub 流程经验
- 场景：把 pc-file-audit 发布为开源仓库（免费使用、社区共建迭代）
- 关键经验：
  1. **GitHub 密码认证已废弃**：git/API 只能用 Token 或 OAuth，不要尝试账号密码
  2. **国内网络**：GitHub releases 资产下载会超时，git 用 `registry.npmmirror.com/-/binary/git-for-windows/` 镜像；api.github.com 可直连
  3. **沙箱内 GCM 不弹浏览器**：Git Credential Manager 的浏览器授权窗口在沙箱/后台会话弹不出来；改用 **GitHub Device Flow**（`POST github.com/login/device/code` → 用户浏览器输设备码 → 轮询 `login/oauth/access_token`），全程可脚本化、用户只需输 8 位码
  4. **curl 传 JSON 到 GitHub API**：PowerShell 内联中文 JSON 会转义出错（"Problems parsing JSON"），用 `[IO.File]::WriteAllText` 写 body 文件 + `--data-binary @file`
  5. token 用环境变量传递、`git credential approve` 存入凭据管理器，避免落盘命令历史
- 发布物：github.com/hulufeng/pc-file-audit（MIT、README/CONTRIBUTING/Issue模板齐备）
- 状态：已合并（"GitHub 发布"流程可复用）

---

## [2026-10-11] 版本残留三连发现（驱动安装包/浏览器旧版/组件池旧版本）
- 场景：用户质疑"扫描不够详细，不应该就这点"，深挖"版本残留"维度后新增可删 1086MB
- ①**驱动安装包**：`C:\Program Files\CONEXANT\Install`（cab/msi 292MB）——驱动装完安装包残留，Program Files 下需提权删
- ②**浏览器旧版本**：`QQBrowser\12.2.5544.400`（2025-02 旧版 271MB）vs `20.1.7233.400`（2026-02 在用）——Application 目录多版本时旧版可删（删前按目录修改时间+主程序版本验证）
- ③**组件池旧版本**：WPS `addons\pool\win-i386` 302 目录=150 组件组，**152 个旧版本目录共 476MB**（qing 3版/ruby 4版）——正则 `^(.*)_(\d+\.\d+\.\d+\.\d+)$` 分组，保留最高版本删其余
- 教训：全盘扫描还要加"版本残留"维度（任何带版本号目录的多版本共存=旧版残留候选）
- 状态：已合并（SKILL.md 深度扫描清单补充"版本残留"）

---

## [2026-10-11] 本机 SendToRecycleBin 被禁用
- 场景：`[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p,'OnlyErrorDialogs','SendToRecycleBin')` 报 "This function is not supported on this system"
- 根因：系统回收站策略/环境禁用了该 API（此机器所有 SendToRecycleBin 均失效，并非个别路径）
- 解法：改用 `Remove-Item -Recurse -Force -ErrorAction SilentlyContinue` 永久删除；删除前先写清单文件确认目标，删除后验证 Test-Path；无回收站兜底=删除不可逆，清单确认尤为重要
- 状态：已合并

---

## [2026-10-11] WinSxS 分析：DISM 输出 GBK 乱码但数字可读 + 可回收 0 判定
- 场景：管理员权限跑 `DISM /Online /Cleanup-Image /AnalyzeComponentStore` 分析 WinSxS
- 现象：中文系统 DISM 输出 GBK 编码，Out-File UTF8 后变乱码，但"组件存储大小 7.79GB / 可回收组件 0 / 推荐清理：否"等数字仍可读
- 根因：DISM 输出用系统代码页（GBK），非 UTF8
- 解法：乱码不影响关键数字读取；若需精确中文可 `chcp 65001` 前置或 `[Console]::OutputEncoding` 调整后重跑
- 结论：**WinSxS 显示 1.93GB 备份组件 ≠ 可清**——以 DISM 官方"可回收组件 0 / 推荐清理 否"为准，/ResetBase 属 L3 禁止
- 状态：已合并

---

## [2026-10-11] GitHub 工具调研：补充扫描检查清单（已并入 SKILL.md）
- 场景：用户质疑扫描不全面，要求去 GitHub 找相关技能优化
- 调研：WinDirStat（目录树）、WizTree（MFT 快速扫描）、Czkawka（重复文件/空文件夹）、CleanOS/WinClean/CATE/PowerClean（清理脚本）、DiskCleaner/UltraTree（PS 模块）
- 借鉴点：①INetCache 系统网络缓存 ②开发者缓存（npm/pip/NuGet/Gradle/Maven）③重复文件（同名同大小→哈希）④Edge/浏览器旧版本目录（删除前验证当前版本）⑤temp 清理加 LastWriteTime>1天过滤 ⑥数据持久化（CleanOS_data.json≈我们的 decisions.md）
- 本机补充扫描结果：INetCache 1MB（忽略）、无开发者缓存、无重复大文件、**Edge 92 是当前在用版本（427MB 不能删）**、无休眠文件、还原点无占用
- 结论：此前清理已全面，补充检查无新可删大项；验证比假设重要
- 状态：已合并（SKILL.md 深度扫描检查清单）

---

## [2026-10-11] Edge"唯一版本目录"不一定是残留
- 场景：扫描发现 `C:\Program Files (x86)\Microsoft\Edge\Application\92.0.902.67`（427MB，msedge.dll 171MB），疑似旧版残留
- 验证：`(Get-Item msedge.exe).VersionInfo.ProductVersion` = 92.0.902.67 → **92 就是当前在用版本**（2014 老机器 Edge 更新长期失败停在 2021 年版）
- 教训：Application 目录下唯一的版本文件夹 = 正在使用的版本；删除前必须验证当前版本（主程序 ProductVersion + 注册表 pv），不能凭"版本老"判断
- 状态：已合并

---

## [2026-10-11] 逐批决策交互模式（用户"一个文件一个文件决定"的实现）
- 场景：用户要求逐个文件告知用途并决定删/留。96,377 个文件不可能逐个交互 → 用"优先级分批 + 目录聚合"模式
- 流程：排除系统文件与程序本体 → 剩余按优先级（日志>缓存>残留>数据>配置）排队 → 每批展示 30-50 项（路径/大小/用途/删除后果）→ 用户整批回复编号 → 执行（进回收站）→ 决策写入 decisions.md
- 用户决策模式观察：用户倾向"编号批量回复"（如"1-10，11-17删除""1234567删""12"），说明表格化编号+建议是高效交互格式
- 关键规则：删除必须进回收站（空间未释放时提示用户清空回收站）；程序本体（Program Files/软件目录下的 exe/dll）默认保留不询问；系统必需文件（PAGEFILE/swapfile）永不删
- 状态：已合并（SKILL.md 可增加"逐批决策"章节）

---

## [2026-10-11] QQ管家残留还可能藏在 D盘根目录
- 场景：卸载 QQ 管家后，除了 AppData/ProgramData 残留，D盘根目录还躺着 15 个文件（QMMemScanner.exe、QMChromeExt.exe、bugreport64.exe、dbgeng.dll、beacon_sdk64.dll、QQPCDownload1975.exe、PacketBlockPage.exe 等）
- 教训：检查软件残留时，除常规目录外还要看**盘符根目录**（卸载器常把运行组件丢根目录）
- 规则：盘根目录出现 `QM*`/`beacon*`/`bugreport*`/`PacketBlock*` 前缀 = QQ管家残留，可删；`PAGEFILE.SYS`/`swapfile.sys`/`hiberfil.sys` 永不删
- 状态：已合并

---

## [2026-10-11] LevelDB 的 000003.log 是数据库组件，不是日志
- 场景：文件级标注把所有 `.log` 都标为"日志可删"，但 Chromium 系应用（豆包/DoubaoWork/浏览器）的 `IndexedDB\...\leveldb\000003.log`、`Local Storage\leveldb\000003.log` 等是 **LevelDB 的 WAL（预写日志）**，属于数据库正在使用的文件
- 教训：判定"日志可删"必须先看路径——路径含 `leveldb` 的 `.log` 一律保留；真正的日志是 `sdk_storage\log\`、`*.Log`（大写）、`logs\` 目录下的
- 规则沉淀：路径含 `\leveldb\` 或 `LevelDB\` → 数据库组件，永不删
- 状态：已合并

---

## [2026-10-11] 全盘文件级最小单位审计（96,377 文件）

### [2026-10-11] 文件级基线记忆已建立
- 本机（联想 G505）已做全盘文件级分析，基线文档：`C:\Users\Administrator\Doubao\chats\2026-10-10\new-chat-2\全盘文件基线记忆库.md`
- 数据源：`全盘文件级用途清单.csv`（96,377 条：路径/大小/文件类型/所属软件）
- 复用规则：用户再问"XX 文件是什么/能不能删"时，先查基线记忆库和 CSV，无需重扫；文件系统变化后需增量重扫（compare 基线）
- 状态：已建立

### [2026-10-11] 文件级标注双维度方法
- 维度1：扩展名 → 用途（.exe=程序/.dll=库/.log=日志/.pak=资源包/.db=数据库/.cfg=配置/.cache=缓存/.wim=系统映像/.msi=安装包）
- 维度2：路径软件归属 → 分组（doubao/tencent/kingsoft/sogou 等 23 个组）
- 工具：annotate_files_level.py（引擎）+ files_all.txt（源数据）
- 状态：待合并（可并入 SKILL.md 或 dir-guide.md）

### [2026-10-11] PowerShell 单引号字符串中反引号不转义
- 场景：`$out += ('{0}`t{1}' -f ...)` 用**单引号**包裹格式串
- 现象：输出的是字面 "`t" 而不是 Tab，Python 按 \t 解析失败（文件数=0）
- 教训：反引号转义只在 PowerShell **双引号**字符串有效；跨语言解析时先验证分隔符
- 状态：已修复（Python 兼容两种分隔符）

### [2026-10-11] 软件残留还可能藏在在用软件的目录树下
- 场景：文件级扫描发现 `D:\Roaming\Tencent\QQPCMgr\QMPrivateEtw.etl`（46MB）
- 现象：QQ 管家已卸载，但其残留（ETL 日志）还在 D:\Roaming\Tencent\ 下，被"腾讯系(在用)"分组掩盖
- 解法：残留检查要按**残留特征文件名**（QMPrivateEtw.etl/360greencore 等）全局搜，而不是只按目录归属
- 状态：待合并

### [2026-10-11] 回收站内容会出现在全盘扫描里
- 场景：文件级扫描包含 `C:\$Recycle.Bin\...\chrome.dll`（186MB 360 残留）
- 现象：SendToRecycleBin 删的 greencore 整包在回收站，占空间但 Shell 计数显示 0（COM 接口口径问题）
- 解法：清空回收站（用户单项确认）才能真正释放；清理后若空间没变，先查回收站实际大小
- 状态：待合并（可并入 fixes.md）

---

## [2026-10-11] 全盘最小粒度审计（5515 条目标注实战）

### [2026-10-11] 360 产品残留有多个藏身点
- 场景：全盘最小粒度扫描，AppData 下发现 336MB 残留
- 现象：`AppData\Roaming\greencore`(336MB) + `GreenCore7z`(2MB) + `AppData\Local\360Chrome/360ChromeX`
- 识别法：查目录内 exe 的 versioninfo（360greencore.exe/360bdoctor.exe/NetmProxy.exe = 360 安全浏览器/卫士）
- 结论：360 系残留分布于 Roaming\greencore、Local\360Chrome*，删前必须确认机器上已无 360 产品
- 状态：可并入 dir-guide.md 残留识别

### [2026-10-11] 浏览器/软件更新器残留的命名规律
- 场景：AppData\Local 下发现 `QianwenUpdater`（通义千问）、`QuarkUpdater`（夸克）、`liebao`（猎豹）、`QMLogEx`（腾讯管家日志）
- 规律：`*Updater` 命名的目录=该软件的更新器残留；`liebao` 是猎豹浏览器内核名；`QM*`=腾讯管家前缀
- 处置：对应软件未安装时全部可删；机器上仍在用的（如夸克在用）只删残留部分
- 状态：可并入 dir-guide.md

### [2026-10-11] 标注正则陷阱：短关键词误匹配
- 场景：标注引擎把 `C:\Program Files\WindowsPowerShell` 和 `Windows Photo Viewer` 误标为"可清"
- 根因：缓存规则里的 `wer`（错误报告目录关键词）子串匹配了 "Power**Shell**" 和 "Photo **Viewer**" 词内的 "wer"
- 教训：短关键词必须加词边界 `\bwer\b`；批量标注规则每加一条都要抽查命中的路径，防止误伤系统目录
- 状态：待合并（可并入 fixes.md）

---

## [2026-10-11] 首次试用：个人目录审计（迭代机制实跑验证）

### [2026-10-11] 同一软件的卸载残留可能分布在多个位置
- 场景：审计用户个人目录，发现 `Documents\QQPCMgr\data\config`（0MB）
- 现象：QQ 管家已卸载，但 C 盘根有 `qqpcmgr_docpro`（52MB）、用户目录 `Documents\QQPCMgr`（空壳）等多处残留
- 根因：软件在多个位置（C 盘根/用户目录/ProgramData）落数据，卸载器只清了部分
- 解法：审计时按**软件名**全局搜残留（`Get-ChildItem C:\ -Recurse -Filter '*QQPCMgr*'` 等），不只看程序目录
- 状态：待合并（可并入 dir-guide.md 残留识别技巧）

### [2026-10-11] 桌面回滚备份目录必须识别为保留项
- 场景：审计 Desktop，发现 `perf_backup\`（StartupApproved.reg / VisualEffects.reg）+ `undo_perf.bat`
- 现象：像是"可清理的备份文件"
- 根因：这是**之前 L2 性能优化时生成的回滚材料**（撤销脚本+注册表备份），删了就无法回滚
- 解法：审计时遇到 `perf_backup`/`undo_*.bat`/`backup*.reg` 等回滚材料，一律 🔴 保留并提示用户其用途
- 状态：待合并（可并入 dir-guide.md 分类规则）

### [2026-10-11] 用户数据可能全在 D 盘，个人目录接近全空
- 场景：扫描 C:\Users\Administrator 的 Desktop/Documents/Downloads 等
- 现象：全部 0MB（只有 desktop.ini 和空壳目录）
- 根因：该用户把个人数据全部放在 D 盘（2定陶天缘 等），C 盘个人目录只是系统默认壳
- 解法：审计用户目录前先看数据盘分布；个人目录空 ≠ 用户没数据，别据此判断"用户没文件"
- 状态：待合并

---

## [2026-10-11] 初次初始化：本次实战经验

### [2026-10-11] 服务文件在 SysWOW64 而服务指向 system32
- 场景：Win10 22H2，开机日志反复报 Service Control Manager 7000"找不到文件"
- 现象：SAService 服务（ImagePath 指向 `C:\Windows\system32\SAsrv.exe`）启动失败
- 根因：32 位程序文件实际安装在 `C:\Windows\SysWOW64\SASrv.exe`，与注册表 ImagePath 不一致
- 解法：全盘搜 `Get-ChildItem C:\ -Recurse -Filter 'SAsrv.exe'` 找到真实位置 → 复制到 system32 补位 → `sc.exe config <服务> start= auto` → `sc.exe start <服务>`
- 状态：已合并（fixes.md 案例1）

### [2026-10-11] 直接改注册表 Start 值 SCM 缓存不认（1058）
- 场景：把服务 Start 从 4 改回 2 后启动仍报 1058"服务被禁用"
- 现象：`Set-ItemProperty` 后 `StartMode=Auto` 但 `sc start` 报 1058
- 根因：服务控制管理器（SCM）缓存服务配置，不认直接写注册表
- 解法：必须走 `sc.exe config <服务> start= auto`（SCM API）再启动
- 状态：已合并（fixes.md 案例2）

### [2026-10-11] 运行中的软件会立即重建已删的空缓存目录
- 场景：清理 441 个空文件夹后复扫仍剩 121 个
- 现象：剩余空目录集中在 Roaming（WPS/QQ）等活跃软件目录
- 根因：WPS/QQ 运行时自动重建 blob_storage/cache 空壳目录
- 解法：删除一次即可，剩余属正常生命周期，**不要反复删**
- 状态：已合并（dir-guide.md 空文件夹清理要点）

### [2026-10-11] SendToRecycleBin 在 C 盘系统目录删除常失败
- 场景：删除 C:\ 下残留目录
- 现象：`[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFileSystemEntry` 抛异常
- 根因：权限/系统目录属性限制
- 解法：try/catch 兜底 `Remove-Item -Recurse -Force`；兜底分支删除**不进回收站**，汇报时如实说明
- 状态：已合并（SKILL.md 常见坑）

### [2026-10-11] PS5.1 跑 UTF-8 无 BOM 脚本中文乱码
- 场景：自写 scan_dirs.ps1 被 PS5.1 执行
- 现象：输出中文全部乱码（标题可辨但内容不可读）
- 根因：PowerShell 5.1 按 ANSI(GBK) 读取无 BOM 的 UTF-8 文件
- 解法：脚本一律 UTF-8 BOM 保存（`[IO.File]::WriteAllText($f,$c,(New-Object Text.UTF8Encoding $true))`）
- 状态：已合并（SKILL.md 常见坑）

### [2026-10-11] 字符串拼盘符路径必须带反斜杠
- 场景：scan_dirs.ps1 里 `$root = "$Drive`:"`（无反斜杠）
- 现象：`Get-ChildItem "C:"` 不列 C:\ 根目录内容
- 根因：PowerShell 中 `C:` 按 drive-relative 解析，非根目录
- 解法：`$root = "$Drive`:\"`
- 状态：已合并（scan_dirs.ps1 已修复）

### [2026-10-11] C 盘根常见卸载残留壳目录
- 场景：C 盘一级目录审计
- 现象：`qqpcmgr_docpro`（QQ 管家文档保护残留 52MB）、`QMDownload`（QQ 下载空目录）、`SteamLibrary`（Steam 卸载后 5MB 空壳）
- 根因：软件卸载不彻底/卸载后残留空壳
- 解法：确认无个人数据后删除（用户点名）
- 状态：待合并（可并入 dir-guide.md 残留识别）

### [2026-10-11] Roaming 里 GUID 命名目录 = 软件残留识别法
- 场景：`D:\Roaming\0F01352E-94DF-4A62-B30E-A19806922546` 148MB 不知是何物
- 现象：GUID 目录名无法判断归属
- 根因：软件（YY 浏览器）以 GUID 命名 Roaming 数据目录
- 解法：找目录内 `*.exe` 读 `VersionInfo.CompanyName/ProductName`（YYExplorer.exe → YY Inc. YY 浏览器）→ 确认是残留后可删
- 状态：已合并（dir-guide.md 残留识别技巧）

### [2026-10-11] 蓝牙 AR3012 老模块开机偶发 HCI 超时
- 场景：BTHUSB 事件 5"命令超时""HCI 事件缺失"
- 现象：开机瞬间 3 条蓝牙错误，之后设备 OK
- 根因：蓝牙 4.0 老模块初始化偶发失败，硬件老化/固件限制
- 解法：无法软件修复；设备状态 OK 即忽略；想升级换 USB 蓝牙 5.0 适配器（10-40 元）
- 状态：待合并（可并入 fixes.md 低危问题）

---
