# Changelog

本项目的版本迭代记录。**每个用户/贡献者的实战经验都会沉淀为一次迭代。**

## [1.0.0] - 2026-10-11

首个开源版本，由"联想 G505 老电脑全盘清理实战"蒸馏而来（实战清出 26GB+ 空间）。

**核心能力**：
- 全盘文件扫描（只读）→ 目录功能识别 → 三档分类 → 用户逐项决策 → 安全清理
- 8 项深度扫描检查清单（还原点/休眠/WinSxS/网络缓存/开发者缓存/重复文件/浏览器旧版/版本残留）
- 决策记忆（decisions.md）：用户删/留决定自动沉淀，同类文件下次直接套用
- 自我迭代协议：每次使用后复盘，经验写回 experience-log.md

**实战验证的经验（已内置）**：
- 版本残留三连：驱动安装包（CONEXANT\Install 292MB）/ 浏览器旧版（QQ浏览器 12.2→20.1 271MB）/ 组件池多版本（WPS 152目录 476MB）
- 回收站被禁用机器的降级策略（清单确认+永久删）
- 清理 temp 加 LastWriteTime 过滤（CleanOS 经验）
- "唯一版本目录=在用版本"验证规则（Edge 92 案例）

**致谢**：GitHub 开源工具 WinDirStat / WizTree / Czkawka / CleanOS / WinClean / CATE / PowerClean 的思路借鉴

## [Unreleased]

- [ ] macOS 目录对照表
- [ ] 英文版 README
- [ ] 重复文件哈希检测脚本
- [ ] 可视化报告（HTML 输出）

> 你的 PR/Issue 会成为下一条 changelog。
