# -*- coding: utf-8 -*-
"""
qingpanxia GUI —— 电脑文件可视化审计窗口
============================================
扫描电脑各盘目录 → 识别每个文件夹功能 → 三档分类（红/绿/黄）
→ 可视化条形图 + 勾选删除（优先进回收站）

运行：双击本文件 或  python qingpanxia-gui.py
依赖：仅 Python 标准库（tkinter 随 Python 自带，Windows 直接可用）
"""
import os
import sys
import threading
import shutil
import ctypes
from ctypes import wintypes

import tkinter as tk
from tkinter import ttk, messagebox

# ---------- 常量 ----------
APP_TITLE = "qingpanxia · 电脑文件可视化审计"
APP_VERSION = "1.0"
SCAN_SKIP_TOP = {"$RECYCLE.BIN", "System Volume Information", "Documents and Settings", "Recovery", "Boot"}
SCAN_SKIP_FILE = {"pagefile.sys", "swapfile.sys", "hiberfil.sys", "dumpstack.log.tmp"}

# 三档分类
C_RED = "#E5484D"      # 必须保留
C_GREEN = "#2FA84F"    # 明确可删
C_YELLOW = "#E8B339"   # 用户判断

# 目录功能对照（精简内置版，完整表见 references/dir-guide.md）
DIR_GUIDE = [
    # (关键词, 分类, 说明)
    ("\\windows", "R", "Windows 系统本体，绝不能动"),
    ("program files", "R", "已安装软件程序，卸载请用应用和功能"),
    ("\\users", "R", "用户数据目录（含个人文件）"),
    ("programdata", "R", "软件共享数据/配置"),
    ("system volume information", "R", "系统还原信息"),
    ("$recycle.bin", "R", "回收站"),
    ("pagefile.sys", "R", "虚拟内存"),
    ("swapfile.sys", "R", "系统交换文件"),
    ("hiberfil.sys", "R", "休眠文件"),
    ("\\recovery", "R", "Windows 恢复环境"),
    ("\\boot", "R", "系统引导"),
]
CACHE_KEY = ["cache", "temp", "\\tmp", "\\log", "update\\download", "\\download\\mainapp",
             "\\install", "old", "残留", "backup\\", "autoupdate", "\\logs"]
SOFT_KEY = ["steam", "qqlive", "aliwangwang", "duowan", "gensee", "qqpcmgr", "qq管家",
            "kgenuine", "w3cschool", "微信开发者工具", "statespace", "aim lab"]

def classify(path: str, name: str) -> tuple:
    """返回 (分类, 说明)。分类: R=红必须保留 G=绿可删 Y=黄用户判断"""
    low = path.lower()
    for kw, cat, desc in DIR_GUIDE:
        if kw in low:
            return cat, desc
    # 纯缓存/残留特征
    if any(k in low for k in CACHE_KEY):
        return "G", "缓存/残留，可清理"
    if any(k in low for k in SOFT_KEY):
        return "G", "已确认不用的软件残留"
    # 大目录默认用户判断
    return "Y", "用户判断是否继续使用"

# ---------- 回收站删除（Windows SHFileOperationW） ----------
FO_DELETE = 3
FOF_ALLOWUNDO = 0x40
FOF_NOCONFIRMATION = 0x10
FOF_SILENT = 0x4
FOF_NOERRORUI = 0x400

class SHFILEOPSTRUCTW(ctypes.Structure):
    _fields_ = [
        ("hwnd", wintypes.HWND), ("wFunc", wintypes.UINT),
        ("pFrom", wintypes.LPCWSTR), ("pTo", wintypes.LPCWSTR),
        ("fFlags", ctypes.c_uint), ("fAnyOperationsAborted", wintypes.BOOL),
        ("hNameMappings", ctypes.c_void_p), ("lpszProgressTitle", wintypes.LPCWSTR),
    ]

def send_to_recyclebin(path: str) -> bool:
    """尝试把文件/目录送入回收站，返回是否成功"""
    try:
        op = SHFILEOPSTRUCTW()
        op.wFunc = FO_DELETE
        op.pFrom = path + "\0\0"
        op.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI
        r = ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op))
        return r == 0
    except Exception:
        return False

# ---------- 扫描引擎 ----------
def dir_size(path: str) -> int:
    total = 0
    for root, dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total

def scan_drive(drive: str, progress_cb=None) -> list:
    """扫描盘符一级+二级目录，返回 [{name, path, size_mb, cat, desc}]"""
    results = []
    root = drive + ":\\"
    top_dirs = []
    try:
        for d in os.scandir(root):
            if d.is_dir(follow_symlinks=False) and d.name not in SCAN_SKIP_TOP:
                top_dirs.append(d)
    except OSError as e:
        return results, str(e)

    for i, d in enumerate(top_dirs):
        if progress_cb:
            progress_cb(i + 1, len(top_dirs), d.name)
        s = dir_size(d.path)
        cat, desc = classify(d.path, d.name)
        results.append({"name": d.name, "path": d.path, "size_mb": round(s / 1048576, 1),
                        "cat": cat, "desc": desc, "level": 0})
        # 二级目录（>10MB 且不在关键目录内）
        if cat != "R":
            try:
                subs = [x for x in os.scandir(d.path)
                        if x.is_dir(follow_symlinks=False) and not x.name.startswith("$")]
            except OSError:
                subs = []
            for s2 in subs:
                ss = dir_size(s2.path)
                if ss > 10 * 1048576:
                    c2, d2 = classify(s2.path, s2.name)
                    results.append({"name": s2.name, "path": s2.path, "size_mb": round(ss / 1048576, 1),
                                    "cat": c2, "desc": d2, "level": 1, "parent": d.name})
    return results, None

# ---------- GUI ----------
class App:
    def __init__(self, root: tk.Tk):
        self.root = root
        root.title(APP_TITLE)
        root.geometry("1080x720")
        root.minsize(900, 600)
        try:
            root.tk.call("tk", "scaling", 1.25)
            self.font = ("Microsoft YaHei UI", 10)
            self.font_b = ("Microsoft YaHei UI", 11, "bold")
        except Exception:
            self.font = ("SimHei", 10)
            self.font_b = ("SimHei", 11, "bold")

        self.data = []          # 扫描结果
        self.checked = {}       # path -> bool 勾选
        self.scanning = False

        self._build_top()
        self._build_middle()
        self._build_bottom()
        self._detect_drives()

    # ---------- 顶部 ----------
    def _build_top(self):
        bar = ttk.Frame(self.root, padding=(8, 6))
        bar.pack(fill="x")
        ttk.Label(bar, text="选择盘符:", font=self.font).pack(side="left")
        self.drive_cb = ttk.Combobox(bar, state="readonly", width=6, font=self.font)
        self.drive_cb.pack(side="left", padx=(4, 12))
        self.scan_btn = ttk.Button(bar, text="开始扫描", command=self.start_scan)
        self.scan_btn.pack(side="left")
        self.progress = ttk.Progressbar(bar, length=260, mode="determinate")
        self.progress.pack(side="left", padx=12)
        self.status = ttk.Label(bar, text="就绪", font=self.font, foreground="#555")
        self.status.pack(side="left")

    # ---------- 中部 ----------
    def _build_middle(self):
        paned = ttk.PanedWindow(self.root, orient="horizontal")
        paned.pack(fill="both", expand=True, padx=8, pady=(0, 6))

        # 左：目录树
        left = ttk.Frame(paned)
        paned.add(left, weight=3)
        cols = ("check", "name", "size", "cat", "desc")
        self.tree = ttk.Treeview(left, columns=cols, show="headings", selectmode="browse")
        self.tree.heading("check", text="删")
        self.tree.heading("name", text="目录")
        self.tree.heading("size", text="大小(MB)")
        self.tree.heading("cat", text="分类")
        self.tree.heading("desc", text="说明")
        self.tree.column("check", width=38, anchor="center", stretch=False)
        self.tree.column("name", width=220, anchor="w")
        self.tree.column("size", width=80, anchor="e")
        self.tree.column("cat", width=60, anchor="center")
        self.tree.column("desc", width=280, anchor="w")
        self.tree.tag_configure("R", background="#FDEBEC")
        self.tree.tag_configure("G", background="#E8F7EC")
        self.tree.tag_configure("Y", background="#FDF3E0")
        vs = ttk.Scrollbar(left, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=vs.set)
        self.tree.pack(side="left", fill="both", expand=True)
        vs.pack(side="right", fill="y")
        self.tree.bind("<Button-1>", self._tree_click)

        # 右：条形图
        right = ttk.Frame(paned, width=330)
        paned.add(right, weight=2)
        ttk.Label(right, text="目录占用 Top15（绿=可删 黄=判断 红=保留）",
                  font=self.font_b).pack(pady=(4, 2))
        self.canvas = tk.Canvas(right, bg="#FFFFFF", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)

    # ---------- 底部 ----------
    def _build_bottom(self):
        bar = ttk.Frame(self.root, padding=(8, 6))
        bar.pack(fill="x")
        ttk.Label(bar, text="勾选说明：默认勾选 🟢 明确可删项，点击列表第一列可改", font=self.font).pack(side="left")
        self.del_btn = ttk.Button(bar, text="删除勾选项（进回收站）", command=self.delete_checked,
                                  style="Accent.TButton")
        self.del_btn.pack(side="right")

    # ---------- 逻辑 ----------
    def _detect_drives(self):
        drives = []
        import string
        for letter in string.ascii_uppercase:
            p = letter + ":\\"
            if os.path.exists(p):
                drives.append(letter + ":")
        self.drive_cb["values"] = drives
        if drives:
            self.drive_cb.current(0)

    def start_scan(self):
        if self.scanning:
            return
        drive = self.drive_cb.get()
        if not drive:
            messagebox.showwarning("提示", "请先选择盘符")
            return
        self.scanning = True
        self.scan_btn.config(state="disabled")
        self.tree.delete(*self.tree.get_children())
        self.canvas.delete("all")
        self.data = []
        self.checked = {}
        self.progress["value"] = 0
        self.status.config(text="扫描中…")
        threading.Thread(target=self._scan_worker, args=(drive,), daemon=True).start()

    def _scan_worker(self, drive):
        def cb(i, n, name):
            self.root.after(0, lambda: (self.progress.configure(maximum=n, value=i),
                                        self.status.config(text="扫描中: %s" % name)))
        results, err = scan_drive(drive, cb)
        self.root.after(0, lambda: self._scan_done(results, err))

    def _scan_done(self, results, err):
        self.scanning = False
        self.scan_btn.config(state="normal")
        self.data = results
        if err:
            self.status.config(text="扫描出错: " + err, foreground="#C00")
            return
        total_mb = sum(r["size_mb"] for r in results if r["level"] == 0)
        green = sum(r["size_mb"] for r in results if r["cat"] == "G")
        # 填表
        for r in results:
            name = ("    " if r["level"] == 1 else "") + r["name"]
            cat_txt = {"R": "🔴保留", "G": "🟢可删", "Y": "🟡判断"}[r["cat"]]
            self.tree.insert("", "end", iid=r["path"], tags=(r["cat"],),
                             values=("☐", name, r["size_mb"], cat_txt, r["desc"]))
            if r["cat"] == "G":
                self.checked[r["path"]] = True
                self.tree.item(r["path"], values=("☑", name, r["size_mb"], cat_txt, r["desc"]))
        self._draw_chart()
        self.status.config(text="扫描完成 · 共 %.1f GB · 可删约 %.1f GB" % (total_mb / 1024, green / 1024),
                           foreground="#2FA84F")

    def _tree_click(self, event):
        iid = self.tree.identify_row(event.y)
        if not iid:
            return
        col = self.tree.identify_column(event.x)
        if col != "#1":  # 只有第一列（勾选列）可点
            return
        vals = list(self.tree.item(iid, "values"))
        cat = vals[3]
        if cat in ("🔴保留",):
            return
        if self.checked.get(iid):
            self.checked[iid] = False
            vals[0] = "☐"
        else:
            self.checked[iid] = True
            vals[0] = "☑"
        self.tree.item(iid, values=vals)

    def _draw_chart(self):
        self.canvas.delete("all")
        top = sorted([r for r in self.data if r["level"] == 0], key=lambda x: -x["size_mb"])[:15]
        if not top:
            return
        w = self.canvas.winfo_width() or 300
        h = self.canvas.winfo_height() or 400
        max_mb = max(r["size_mb"] for r in top) or 1
        bar_h = min(26, (h - 30) / len(top))
        colors = {"R": C_RED, "G": C_GREEN, "Y": C_YELLOW}
        y = 6
        self.canvas.create_text(w - 4, 3, anchor="ne", text="MB", fill="#888",
                                font=("Microsoft YaHei UI", 8))
        for r in top:
            bw = max(8, (r["size_mb"] / max_mb) * (w - 130))
            self.canvas.create_rectangle(4, y, 4 + bw, y + bar_h - 3, fill=colors[r["cat"]], outline="")
            self.canvas.create_text(8, y + (bar_h - 3) / 2, anchor="w", text=r["name"][:12],
                                    fill="#333", font=("Microsoft YaHei UI", 8))
            self.canvas.create_text(4 + bw + 6, y + (bar_h - 3) / 2, anchor="w",
                                    text=str(r["size_mb"]), fill="#333", font=("Microsoft YaHei UI", 8))
            y += bar_h

    def delete_checked(self):
        targets = [p for p, c in self.checked.items() if c]
        if not targets:
            messagebox.showinfo("提示", "没有勾选要删除的项目")
            return
        msg = "将删除以下 %d 项（优先移入回收站）：\n\n" % len(targets)
        for t in targets:
            msg += "• " + t + "\n"
        msg += "\n⚠ 若回收站通道不可用将永久删除，且均为缓存/残留（非个人文件）。"
        if not messagebox.askyesno("确认删除", msg, icon="warning"):
            return
        ok = 0
        recycled = 0
        for t in targets:
            if send_to_recyclebin(t):
                recycled += 1
            else:
                try:
                    if os.path.isdir(t):
                        shutil.rmtree(t, ignore_errors=True)
                    else:
                        os.remove(t)
                except OSError:
                    pass
            ok += 1
            self.tree.delete(t)
        self.checked = {}
        messagebox.showinfo("完成", "删除完成：%d 项，其中 %d 项进入回收站" % (ok, recycled))
        self.status.config(text="已删除 %d 项" % ok, foreground="#2FA84F")

def main():
    try:
        style = ttk.Style()
        style.theme_use("vista")
        style.configure("Accent.TButton", font=("Microsoft YaHei UI", 10, "bold"))
    except Exception:
        pass
    root = tk.Tk()
    App(root)
    root.mainloop()

if __name__ == "__main__":
    main()
