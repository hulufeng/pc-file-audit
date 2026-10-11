# Windows 常见目录功能对照表

用途：审计时把扫描结果对照本表，快速判定每个目录"是什么、能不能删"。

## 目录速查

| 目录 | 功能 | 分类 |
|---|---|---|
| `C:\Windows` | 系统本体（System32 核心、WinSxS 组件存储） | 🔒 绝不能动 |
| `C:\Program Files` / `(x86)` | 已安装软件程序 | 🔒 卸载走"应用和功能"，不手删 |
| `C:\Program Files\WindowsApps` | 商店 UWP 应用（常占 3-5GB） | ⚠️ 在设置里卸载不用的，不手删 |
| `C:\ProgramData` | 软件共享数据/配置 | 🔒 只能清明确 cache 子目录 |
| `C:\Recovery` | Windows 恢复环境（Winre.wim） | 🔒 系统恢复用 |
| `C:\Boot` / `System Volume Information` / `Documents and Settings` | 引导/还原/兼容链接 | 🔒 |
| `C:\Users\<名>\AppData\Local` | 程序数据+缓存（浏览器缓存大头） | 🟢 清 cache 子目录；🟡 其余用户判断 |
| `C:\Users\<名>\AppData\Roaming` | 软件配置/用户数据（WPS/QQ/微信等） | 🔒 整体不删，🟢 清纯 cache 子目录 |
| `pagefile.sys` / `swapfile.sys` / `hiberfil.sys` | 虚拟内存/休眠 | 🔒 不直接删文件 |
| `C:\Windows.old` | 旧系统回退 | ⚠️ 不可逆单独确认后走 cleanmgr 删 |
| `C:\Windows\SoftwareDistribution\Download` | 更新缓存 | 🟢 停 wuauserv 后可清 |
| `C:\Windows\Temp` / `%TEMP%` | 临时文件 | 🟢 可清（占用中跳过） |
| `C:\Windows\Logs` / `Minidump` / `MEMORY.DMP` | 日志/蓝屏转储 | 🟢 默认可清（排查故障时保留） |
| `$RECYCLE.BIN` | 回收站 | ⚠️ 需用户单项确认才清空 |
| `SteamLibrary` / `QQDownload` / `QMDownload` 等 | 平台下载/残留空壳 | 🟡 展开确认后删 |
| `Roaming\<GUID 长串>` | 常为某软件残留（展开看 EXE 版本信息识别厂商，如 YY 浏览器） | 🟡 识别后删 |

## 分类规则

- **🔴 必须保留**：系统目录、驱动（声卡/显卡/触控板/网卡 OEM 工具）、杀毒/安全软件、在用的软件、个人文件（桌面/文档/下载/图片/视频）、软件配置数据
- **🟢 明确可删**：已卸载软件的残留目录、空目录（含隐藏文件都无）、纯缓存（浏览器 Cache、临时文件、日志、更新缓存）、过期安装包
- **🟡 用户判断**：不常用的软件本体/数据（QQ 浏览器、游戏盒子、会议软件等）——列出"你还在用吗"判断点

## 残留识别技巧

- GUID 命名的 Roaming 目录：找里面的 `*.exe` → 读 `VersionInfo.CompanyName` / `ProductName` 识别厂商（如 YYExplorer.exe → YY 浏览器）
- 卸载过的软件残留：`服务管理器` 报 7000"找不到文件" → 查 `HKLM:\SYSTEM\CurrentControlSet\Services\<名>` 的 ImagePath 定位来源
- 软件数据目录 vs 纯缓存：目录名含 `cache`/`Cache`/`blob_storage`/`Temp` 且里面全是指定格式缓存 → 可清；含 `Users`/`Data`/`Config`/`Settings` → 保留

## 空文件夹清理要点

- 判定真空：`@(Get-ChildItem $dir -Force).Count -eq 0`（-Force 才能看到隐藏文件）
- 跳过：`$RECYCLE.BIN`、`System Volume Information`、`Roaming\Microsoft`（系统密钥结构）
- 删除后运行中的软件会重建空壳目录——剩余少量新空目录属正常，不反复删
- 空目录不占空间，清理价值在整洁；先扫出数量分布再删，勿逐个问用户
