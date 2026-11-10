#Requires -Version 5.1
<#
.SYNOPSIS
    蓝牙发送 (BtSend) 从零安装脚本
.DESCRIPTION
    一键编译 BtSend.exe 并在"发送到"菜单中创建快捷方式。
    解决 Windows 蓝牙文件传送 (fsquirt.exe) 只能发送单个文件的限制。
.PARAMETER Uninstall
    卸载 BtSend（删除 exe、日志、flag、快捷方式）
.PARAMETER AutoNext
    安装后写入 autonext.flag（发送后自动点击"下一步"）
.EXAMPLE
    .\Install-BtSend.ps1
    .\Install-BtSend.ps1 -AutoNext
    .\Install-BtSend.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$AutoNext
)

$ErrorActionPreference = 'Stop'

# ---------- 路径常量 ----------
$script:InstallDir = Join-Path $env:LOCALAPPDATA 'BtSendTo'
$script:Exe        = Join-Path $script:InstallDir 'BtSend.exe'
$script:LogFile    = Join-Path $script:InstallDir 'bt-send.log'
$script:FlagFile   = Join-Path $script:InstallDir 'autonext.flag'
$script:SendTo     = [Environment]::GetFolderPath('SendTo')
$script:LnkPath    = Join-Path $script:SendTo '蓝牙发送.lnk'

# ---------- 输出辅助 ----------
function Write-Step { param($m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-WarnMsg { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[x] $m" -ForegroundColor Red }

# ---------- 前置检查 ----------
function Test-Prerequisites {
    $ok = $true

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Err "需要 PowerShell 5.1+（当前：$($PSVersionTable.PSVersion)）"
        $ok = $false
    }

    # fsquirt.exe 是 Windows 自带蓝牙文件传送程序
    $fsquirt = Join-Path $env:windir 'System32\fsquirt.exe'
    if (-not (Test-Path -LiteralPath $fsquirt)) {
        Write-WarnMsg "未找到 fsquirt.exe（$fsquirt）— 目标机器可能没有蓝牙文件传送组件"
        # 不阻断安装，允许用户在需要的机器上重试
    } else {
        Write-Ok "fsquirt.exe 存在"
    }

    if (-not (Test-Path -LiteralPath $script:SendTo)) {
        Write-Err "SendTo 目录不可用：$script:SendTo"
        $ok = $false
    } else {
        Write-Ok "SendTo 目录：$script:SendTo"
    }

    return $ok
}

# ---------- 编译 ----------
function Invoke-Compile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Output
    )

    # 写临时 .cs（带 BOM 的 UTF-8，保证 csc 正确处理中文注释）
    $tempCs = Join-Path $env:TEMP ('BtSend_' + [guid]::NewGuid().ToString('N') + '.cs')
    try {
        [System.IO.File]::WriteAllText($tempCs, $Source,
            (New-Object System.Text.UTF8Encoding($true)))

        # 找 csc.exe（.NET Framework 4.x 编译器的稳定路径）
        $cscCandidates = @(
            (Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
            (Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
        )
        $csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $csc) {
            throw "未找到 .NET Framework 4.x 编译器 (csc.exe)。请安装 .NET Framework 4.5+ 后重试。"
        }
        Write-Ok "编译器：$csc"

        $cscArgs = @(
            '/nologo'
            '/target:winexe'
            "/out:$Output"
            '/optimize+'
            '/platform:anycpu'
            $tempCs
        )
        $compileOut = & $csc @cscArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ("csc 编译失败（exit=$LASTEXITCODE）：`n" + ($compileOut -join "`n"))
        }
        if (-not (Test-Path -LiteralPath $Output)) {
            throw "编译完成但未生成 $Output"
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempCs) {
            Remove-Item -LiteralPath $tempCs -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------- 卸载 ----------
function Invoke-Uninstall {
    Write-Step '开始卸载 BtSend...'

    Get-Process -Name BtSend -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300

    # 清掉快捷方式（包括历史遗留的旧名字）
    $staleShortcuts = @(
        $script:LnkPath
        (Join-Path $script:SendTo '蓝牙设备（脚本）.lnk')
        (Join-Path $script:SendTo '蓝牙文件传送(修复).lnk')
    )
    foreach ($s in $staleShortcuts) {
        if (Test-Path -LiteralPath $s) {
            Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue
            Write-Ok "已删除：$s"
        }
    }

    if (Test-Path -LiteralPath $script:InstallDir) {
        Remove-Item -LiteralPath $script:InstallDir -Recurse -Force
        Write-Ok "已删除安装目录：$script:InstallDir"
    }

    Write-Ok '卸载完成'
}

# ---------- 安装 ----------
function Invoke-Install {
    Write-Step '开始安装 BtSend...'

    # 1) 停掉旧实例
    Get-Process -Name BtSend -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300

    # 2) 建目录
    if (-not (Test-Path -LiteralPath $script:InstallDir)) {
        New-Item -ItemType Directory -Force -Path $script:InstallDir | Out-Null
    }
    Write-Ok "安装目录：$script:InstallDir"

    # 3) 清旧 exe
    if (Test-Path -LiteralPath $script:Exe) {
        Remove-Item -LiteralPath $script:Exe -Force
        Start-Sleep -Milliseconds 300
    }

    # 4) 编译
    Write-Step '编译 BtSend.exe...'
    Invoke-Compile -Source $csSource -Output $script:Exe
    Write-Ok "编译成功：$script:Exe"

    # 5) 快捷方式
    Write-Step '创建"发送到"快捷方式...'
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($script:LnkPath)
    $lnk.TargetPath       = $script:Exe
    $lnk.WorkingDirectory = $script:InstallDir
    $lnk.IconLocation     = "$env:windir\System32\fsquirt.exe,0"
    $lnk.Description      = '蓝牙发送 - 修复 Windows 蓝牙文件传送'
    $lnk.Save()
    Write-Ok "快捷方式：$script:LnkPath"

    # 6) 可选 autonext
    if ($AutoNext) {
        New-Item -ItemType File -Force -Path $script:FlagFile | Out-Null
        Write-Ok "已启用自动点击"下一步"：$script:FlagFile"
    }

    # 7) 冒烟验证：启动一次 exe（无参 → 记 no valid files → 退出），确认不是坏的 PE
    Write-Step '冒烟验证...'
    $proc = Start-Process -FilePath $script:Exe -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 800
    if (-not $proc.HasExited) {
        $proc.Kill()
        Write-WarnMsg 'BtSend 未在预期时间内退出，已强制结束（可能是环境差异，不影响使用）'
    } else {
        Write-Ok "BtSend 启动正常（退出码 $($proc.ExitCode)）"
    }
}

# ---------- C# 源码 ----------
$csSource = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BtSendProgram
{
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetDlgItem(IntPtr h, int id);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, StringBuilder l);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);

    const uint WM_SETTEXT = 0x000C, WM_GETTEXT = 0x000D, WM_COMMAND = 0x0111, BM_CLICK = 0x00F5;
    static string LogPath;

    static void Log(string m)
    {
        try { File.AppendAllText(LogPath, DateTime.Now.ToString("MM-dd HH:mm:ss.fff ") + m + Environment.NewLine); } catch { }
    }
    static string Cls(IntPtr h) { StringBuilder s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    static string Cap(IntPtr h) { StringBuilder s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
    static string Txt(IntPtr h) { StringBuilder s = new StringBuilder(8192); SendMessage(h, WM_GETTEXT, (IntPtr)s.Capacity, s); return s.ToString(); }

    static List<IntPtr> Tops()
    {
        List<int> pids = new List<int>();
        foreach (Process p in Process.GetProcessesByName("fsquirt")) { pids.Add(p.Id); p.Dispose(); }
        List<IntPtr> list = new List<IntPtr>();
        EnumWindows(delegate (IntPtr h, IntPtr x) {
            uint w; GetWindowThreadProcessId(h, out w);
            if (pids.Contains((int)w) && IsWindowVisible(h)) list.Add(h);
            return true;
        }, IntPtr.Zero);
        return list;
    }
    static List<IntPtr> Kids(IntPtr parent)
    {
        List<IntPtr> list = new List<IntPtr>();
        EnumChildWindows(parent, delegate (IntPtr h, IntPtr x) { list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }

    static bool FindPage(out IntPtr top, out IntPtr page, out IntPtr edit, out IntPtr browse)
    {
        top = page = edit = browse = IntPtr.Zero;
        foreach (IntPtr t in Tops())
        {
            if (Cls(t) != "NativeHWNDHost") continue;
            foreach (IntPtr c in Kids(t))
            {
                if (Cls(c) != "Button" || !IsWindowVisible(c)) continue;
                string cap = Cap(c);
                if (cap.IndexOf("\u6D4F\u89C8") < 0 && cap.IndexOf("Browse", StringComparison.OrdinalIgnoreCase) < 0) continue;
                IntPtr pg = GetParent(c);
                foreach (IntPtr s in Kids(pg))
                {
                    if (Cls(s) == "Edit" && IsWindowVisible(s) && GetParent(s) == pg)
                    { top = t; page = pg; edit = s; browse = c; return true; }
                }
            }
        }
        return false;
    }

    static IntPtr FindOpenDlg(out IntPtr fileEdit)
    {
        fileEdit = IntPtr.Zero;
        foreach (IntPtr t in Tops())
        {
            if (Cls(t) != "#32770") continue;
            IntPtr combo = GetDlgItem(t, 0x47C);
            if (combo == IntPtr.Zero)
                foreach (IntPtr c in Kids(t))
                    if (Cls(c) == "ComboBoxEx32" && IsWindowVisible(c) && GetParent(c) == t) { combo = c; break; }
            if (combo == IntPtr.Zero) continue;
            foreach (IntPtr c in Kids(combo))
                if (Cls(c) == "Edit") { fileEdit = c; return t; }
        }
        return IntPtr.Zero;
    }

    static void Submit(IntPtr dlg, IntPtr edit, string text)
    {
        SendMessage(edit, WM_SETTEXT, IntPtr.Zero, text);
        Thread.Sleep(150);
        PostMessage(dlg, WM_COMMAND, (IntPtr)1, GetDlgItem(dlg, 1));
        Log("submitted: " + text);
    }

    public static int Main(string[] args)
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        LogPath = Path.Combine(baseDir, "bt-send.log");
        bool autoNext = File.Exists(Path.Combine(baseDir, "autonext.flag"));

        List<string> files = new List<string>();
        foreach (string a in args) { try { if (File.Exists(a)) files.Add(Path.GetFullPath(a)); } catch { } }
        if (files.Count == 0) { Log("no valid files"); return 1; }

        string dir0 = Path.GetDirectoryName(files[0]);
        List<string> same = new List<string>();
        foreach (string f in files)
        {
            if (string.Equals(Path.GetDirectoryName(f), dir0, StringComparison.OrdinalIgnoreCase)) same.Add(f);
            else Log("skipped (different folder): " + f);
        }
        Log("start: " + string.Join(" | ", same.ToArray()));

        Process.Start(Path.Combine(Environment.SystemDirectory, "fsquirt.exe"), "-send");
        DateTime start = DateTime.Now;

        IntPtr top, page, wizEdit, browse;
        while (!FindPage(out top, out page, out wizEdit, out browse))
        {
            if ((DateTime.Now - start).TotalMinutes > 10) { Log("timeout: file page"); return 2; }
            if ((DateTime.Now - start).TotalSeconds > 5 && Process.GetProcessesByName("fsquirt").Length == 0) { Log("fsquirt exited"); return 2; }
            Thread.Sleep(200);
        }
        Log("file page found");
        Thread.Sleep(300);

        PostMessage(page, WM_COMMAND, (IntPtr)GetDlgCtrlID(browse), browse);
        DateTime t0 = DateTime.Now; bool fb = false;
        IntPtr fileEdit; IntPtr dlg;
        while ((dlg = FindOpenDlg(out fileEdit)) == IntPtr.Zero)
        {
            double s = (DateTime.Now - t0).TotalSeconds;
            if (!fb && s > 3) { PostMessage(browse, BM_CLICK, IntPtr.Zero, IntPtr.Zero); fb = true; Log("fallback BM_CLICK"); }
            if (s > 15) { Log("open dialog not found"); return 3; }
            Thread.Sleep(150);
        }
        Log("open dialog found");
        Thread.Sleep(300);

        if (same.Count == 1) Submit(dlg, fileEdit, same[0]);
        else
        {
            Submit(dlg, fileEdit, dir0);
            Thread.Sleep(800);
            IntPtr e2; IntPtr d2 = FindOpenDlg(out e2);
            if (d2 == IntPtr.Zero) { Log("dialog lost after navigate"); return 4; }
            StringBuilder sb = new StringBuilder();
            foreach (string f in same) sb.Append('"').Append(Path.GetFileName(f)).Append("\" ");
            Submit(d2, e2, sb.ToString().Trim());
        }

        t0 = DateTime.Now; string got = "";
        while ((DateTime.Now - t0).TotalSeconds < 10)
        {
            IntPtr e3;
            if (FindOpenDlg(out e3) == IntPtr.Zero) { got = Txt(wizEdit); if (got.Length > 0) break; }
            Thread.Sleep(200);
        }
        Log("wizard box = [" + got + "]");
        if (got.Length == 0) { Log("not filled, left to user"); return 5; }

        if (autoNext)
        {
            Thread.Sleep(300);
            foreach (IntPtr c in Kids(top))
            {
                if (Cls(c) == "Button" && IsWindowVisible(c) && Cap(c).IndexOf("\u4E0B\u4E00\u6B65") >= 0)
                { SetForegroundWindow(top); PostMessage(c, BM_CLICK, IntPtr.Zero, IntPtr.Zero); Log("clicked Next"); break; }
            }
        }
        return 0;
    }
}
'@

# ---------- 主入口 ----------
try {
    if ($Uninstall) {
        Invoke-Uninstall
        exit 0
    }

    if (-not (Test-Prerequisites)) {
        Write-Err '环境检查未通过，安装中止'
        exit 1
    }

    Invoke-Install

    Write-Host ''
    Write-Host '=========================================' -ForegroundColor Green
    Write-Host '  安装完成！' -ForegroundColor Green
    Write-Host '=========================================' -ForegroundColor Green
    Write-Host ''
    Write-Host "安装位置 : $script:InstallDir"
    Write-Host "快捷方式 : $script:LnkPath"
    Write-Host "日志     : $script:LogFile"
    Write-Host ''
    Write-Host '使用方法：' -ForegroundColor Yellow
    Write-Host '  1. 资源管理器中选中一个或多个文件'
    Write-Host '  2. 右键 → 发送到 → 蓝牙发送'
    Write-Host '  3. 在 fsquirt 向导中确认发送'
    Write-Host ''
}
catch {
    Write-Err "安装失败：$_"
    if ($_.ScriptStackTrace) { Write-Err $_.ScriptStackTrace }
    exit 1
}
