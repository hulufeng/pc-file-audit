# 用户决策记录（decisions）

本文件记录用户对每个文件的删除/保留决策，是 qingpanxia 的**决策记忆**。
格式：`路径 | 决策 | 时间`。新条目在上。后续审计同类文件时，直接按已记录决策执行（用户可随时推翻）。

---

## 2026-10-11 第六批（Defender缓存+搜狗旧组件）— 用户决策：全部删除

**已删**：
- `D:\下载软件\SogouInput\Components\SogouFlash\1.0.0.181`（搜狗Flash旧版）| 4MB
- `D:\下载软件\SogouInput\Components\PicFace\1.1.0.1737`（搜狗表情旧版）| 9MB

**保留（删除失败-被Defender服务锁定，且属安全规则L3：不停杀毒服务）**：
- `C:\ProgramData\Microsoft\Windows Defender\Scans`（扫描缓存 250MB）
- `C:\ProgramData\Microsoft\Windows Defender\Definition Updates\Backup`（病毒库备份 224MB）
→ Defender 自动管理，删除需停杀毒服务=禁止操作，放弃

---

## 2026-10-11 第五批（版本残留/驱动安装包）— 用户决策：全部删除 ✅ 1086MB

**删**：
- `C:\Program Files\CONEXANT\Install`（声卡驱动安装包缓存：dolbygui.cab 130MB+saii.cab 38MB+DolbyGUI msi×4 128MB+LangDlls 28MB）| 292MB
- `D:\Program Files\Tencent\QQBrowser\12.2.5544.400`（QQ浏览器旧版本，在用 20.1.7233.400）| 271MB
- WPS 组件池旧版本 122 个目录（`D:\Roaming\kingsoft\wps\addons\pool\win-i386`，保留每组件最高版本）| 476MB

**关键经验**：
- 这台机器 **SendToRecycleBin 被系统禁用**（"This function is not supported on this system"）→ 删除只能 Remove-Item 永久删（无回收站兜底，删除前务必先列清单确认）
- Program Files 下删除需管理员提权（require_escalated）
- 组件池/浏览器 Application 目录的**多版本共存 = 旧版本残留**，保留最高版本删其余（qing 3版/ruby 4版）

---

## 2026-10-11 WinSxS 组件存储分析（DISM 官方，管理员权限）

- 组件存储总大小 7.79GB / 实际 7.74GB（正常组件 5.80GB + 备份禁用组件 1.93GB）
- **可回收组件：0，官方推荐清理：否** → 不清理（备份组件用于补丁回滚，/ResetBase 属 L3 禁止）
- 全机深层扫描 7 项至此全部完成，结论：**无新增可删大项，此前清理已全面**

---

## 2026-10-11 补充深度扫描结论（GitHub 调研验证）

- INetCache 系统网络缓存：1MB → 忽略
- 开发者缓存（npm/pip/NuGet/Gradle/Maven）：无 → 无需处理
- 重复大文件（>40MB 同名同大小）：无 → 无需处理
- **Edge 92.0.902.67（427MB）：验证为当前在用版本 → 保留**（老机器 Edge 更新失败停在旧版，不是残留）
- 休眠文件/还原点：无占用 → 无需处理
- **结论：此前逐批清理已全面，无新增可删大项**

---

## 2026-10-11 第四批（最后残留）— 用户决策：删除 1、2

**删**：
- `D:\Roaming\Tencent\QQLive`（腾讯视频卸载残留配置）| 删 | 8MB
- `D:\Roaming\Code\Cache`（VS Code 缓存）| 删 | 6MB

**保留**：`D:\Roaming\kingsoft\hiddenfonts`（WPS 字体）、百度网盘运行数据（BaiduYunGuanjia/BaiduYunKernel）——用户在用网盘

---

## 2026-10-11 第四批补充：整体决策流程完结

4 批逐文件决策全部完成并记录。累计释放约 3GB+（QQ管家全套残留/AimLab/展视/阿里/Steam/腾讯视频/多玩/金山壁纸/微信开发者工具/W3Cschool/QQ表情气泡/各类日志缓存）。
待办：豆包退出后清 `Default\Cache` 26MB + `sdk_storage\log` 386MB。

---

## 2026-10-11 第三批（沙箱产物+待判断软件）— 用户决策：全部删除

**删**：
- `C:\...\Doubao\User Data\sandbox_runtime\downloads`（豆包沙箱临时下载）| 删 | 227MB
- `C:\...\Doubao\User Data\Default\Cache`（豆包浏览器缓存）| 删 | 26MB（豆包运行中占用，待退出后清）
- `D:\Roaming\Gensee`（展视互动会议客户端）| 删 | 97MB
- `D:\Roaming\AliWorkbench`、`TaobaoProtect`（阿里旺旺/千牛/淘宝保护）| 删 | 34MB
- `C:\Program Files (x86)\Steam`、`Common Files\Steam`、`AppData\Local\Steam`（游戏平台）| 删 | 36MB
- `D:\Program Files\Tencent\QQLive`（腾讯视频）| 删 | ~400MB
- `D:\Roaming\Tencent\QQ\Misc\MsgBubble`（QQ聊天气泡）| 删 | 33MB

> 用户确认：不再使用展视互动/阿里旺旺千牛/Steam/腾讯视频。

---

## 2026-10-11 第二批（D盘残留+缓存类）— 用户决策：全部删除

**删**：
- D盘根目录 QQ 管家残留全套（QMMemScanner/QMMemScanner64/bugreport64/dbgeng/dbghelp/dr64/beacon_sdk64/QMChromeExt/QMExtInstaller/extension.crx/QQPCDownload1975/PacketBlockPage×3/ExtensionAgent/InstallFilterRules/PopupConfig/com.qq.qqpcmgr.json）| ~15MB
- `D:\DumpStack.log.tmp` | 删
- `D:\Roaming\Tencent\QQ\Skins\FunChat`（QQ动画表情缓存）| 删 | ~270MB
- `D:\Roaming\duowan`（多玩游戏盒）| 删 | 122MB
- `D:\Roaming\khealtheye\wallpaper`（金山健康壁纸）| 删 | 60MB
- `D:\Roaming\kingsoft\office6\cache`（WPS缓存）| 删 | 36MB
- `D:\Roaming\W3Cschool`（教程工具）| 删 | 44MB
- `D:\Roaming\Tencent\微信开发者工具`（小程序开发工具）| 删 | 126MB
- `%USERPROFILE%\AppData\Local\Doubao\User Data\gecko_cache`（豆包网页缓存）| 删 | 279MB

**保留**：`D:\PAGEFILE.SYS`（虚拟内存）、`C:\swapfile.sys`（系统交换）——系统必需，永不删

> 经验沉淀：QQ管家卸载残留还藏在 **D盘根目录**（QMMemScanner.exe 等 15 个文件），检查残留必须看盘根目录。

---

## 2026-10-11 第一批（日志/残留类）— 用户决策：全部删除

- `%USERPROFILE%\AppData\LocalLow\Statespace\`（Aim Lab 残留整组）| 删 | 30MB
- `C:\ProgramData\Tencent\GameAssist\QM*.Log`（QQ管家卸载日志）| 删
- `C:\ProgramData\Tencent\QQPCMgrEnterprise\QMPrivilege.dll.log` | 删
- `%USERPROFILE%\AppData\Local\DoubaoWork\User Data\sdk_storage\log\saman_*.log` | 删 | 42MB（占用跳过）
- `%USERPROFILE%\.codebuddy\logs\`、`.sheetagent\logs\` | 删
- `C:\DumpStack.log.tmp` | 删

**用户明确保留**：`C:\Boot\BCD.LOG*`（系统启动配置）、所有 `*.leveldb\000003.log`（LevelDB 数据库 WAL，不能删）

## 2026-10-11 首批删除执行

- `%USERPROFILE%\AppData\LocalLow\Statespace\`（Aim Lab 残留整组）| 删 | 30MB
- `C:\ProgramData\Tencent\GameAssist\QM*.Log`（QQ管家卸载日志）| 删
- `C:\ProgramData\Tencent\QQPCMgrEnterprise\QMPrivilege.dll.log` | 删
- `%USERPROFILE%\AppData\Local\DoubaoWork\User Data\sdk_storage\log\saman_*.log` | 删 | 42MB
- `%USERPROFILE%\.codebuddy\logs\` | 删
- `%USERPROFILE%\.sheetagent\logs\` | 删
- `C:\DumpStack.log.tmp` | 删

**保留**：`C:\Boot\BCD.LOG*`（系统启动配置）、所有 `*.leveldb\000003.log`（LevelDB WAL=数据库组件）
