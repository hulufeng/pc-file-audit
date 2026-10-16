# 实战修复案例库

从真实机器（联想 G505 / Win10 22H2 / 4GB 内存）遇到的问题中沉淀的修复方法。遇到同类问题直接套用。

## 案例1：服务启动失败 7000 —— "找不到文件"，但文件其实在

**现象**：开机日志反复报 `Service Control Manager 7000：SAService 服务启动失败 - The system cannot find the file specified`

**排查**：
1. `Get-CimInstance Win32_Service -Filter "Name='SAService'"` 看 ImagePath（本例指向 `C:\Windows\system32\SAsrv.exe`）
2. `Test-Path` 确认 system32 里确实没有
3. **全盘搜**：`Get-ChildItem C:\ -Recurse -Filter 'SAsrv.exe'` —— 发现文件实际在 `C:\Windows\SysWOW64\SASrv.exe`（32位目录）和安装源里
4. **根因**：服务注册表指向 system32，但文件装在 SysWOW64（32位程序）→ 路径不一致

**修复**：
```powershell
Copy-Item 'C:\Windows\SysWOW64\SASrv.exe' 'C:\Windows\system32\SAsrv.exe' -Force   # 文件补位
sc.exe config SAService start= auto        # 必须走 SCM，直接改注册表不生效！
sc.exe start SAService                     # 验证 Running
```

## 案例2：改注册表 Start 值后服务仍报 1058（SCM 缓存）

**现象**：`Set-ItemProperty ... Start=2` 后 `sc start` 仍报 1058（服务被禁用），`StartMode` 却显示 Auto

**根因**：服务控制管理器（SCM）缓存服务配置，直接改注册表它不认

**修复**：用 `sc.exe config <服务> start= auto`（走 SCM API 更新），再 `sc.exe start <服务>`。恢复禁用同理 `sc.exe config <服务> start= disabled`。

## 案例3：卸载软件后 SideBySide 78 错误刷屏

**现象**：Application 日志大量 `SideBySide 78：Activation context generation failed for "C:\Program Files (x86)\Tencent\QQPCMgr\...\QQPCTray.exe"`

**结论**：这是**已卸载软件的 manifest 残留**在尝试加载。随软件卸载自动消失，无需处理。排查时先看 Message 里的程序路径——路径对应的软件已删 = 可忽略。

## 案例4：Clear-RecycleBin 一次清不净

**现象**：`Clear-RecycleBin -Force` 后回收站仍有几百 MB（如 D:\$RECYCLE.BIN 遗留 658MB）

**修复**：清后重测回收站大小（`(New-Object -ComObject Shell.Application).NameSpace(0xA).Items() | Measure-Object Size -Sum`），非 0 则：
```powershell
Remove-Item 'D:\$RECYCLE.BIN\*' -Recurse -Force -ErrorAction SilentlyContinue
```

## 案例5：删除目录报 "system call level is not correct"

**现象**：`Remove-Item` 或 .NET `DeleteDirectory` 对 `C:\Program Files (x86)\...` 报该错

**修复**：换 `Remove-Item <路径> -Recurse -Force` 直接重试可成功；两种方式都失败的（权限/占用），报告用户，不要强删。

## 案例6：卸载残留服务/空壳目录识别

- 服务 7000 找不到文件 → 查 `HKLM:\SYSTEM\CurrentControlSet\Services\<名>` 的 `ImagePath` + `DisplayName` 确认来源（Conexant SmartAudio 等 OEM 组件要谨慎，文件缺失≠驱动坏了——先查 `Get-CimInstance Win32_SoundDevice` 确认硬件驱动状态）
- GUID 命名的 Roaming 目录 → 找目录内 `*.exe` 读 `VersionInfo`（CompanyName/ProductName）识别厂商

## 通用排查顺序

1. 看现象 → 查事件日志定位（System/Application 的 Error，注意 Id 和 ProviderName）
2. 读 Message 里的**路径**（通常是线索：哪个程序/文件）
3. 验证路径/文件是否存在 → 定位根因
4. 最小修改修复（补文件/改配置），记录原值，可回滚
5. 修复后验证（服务 Running、错误不再产生）
