// Rooms 启动器 —— 双击导出每局全部房间明细
// 编译：csc /target:exe /out:tools\Rooms.exe tools\RoomsLauncher.cs
//
// 做的事等价于：
//   powershell -File tools\luarun.ps1 tests\rooms_dump.lua
// 然后把生成的 _logs\rooms-*.txt 打开。
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class RoomsLauncher
{
    static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }

        string toolsDir = AppDomain.CurrentDomain.BaseDirectory;
        // exe 可能在 tools\ 里，也可能被拖到别处；两种都试着找项目根
        string root = null;
        foreach (string cand in new string[] {
            Path.GetDirectoryName(toolsDir.TrimEnd('\\')),
            toolsDir })
        {
            if (cand != null && File.Exists(Path.Combine(cand, "tests", "rooms_dump.lua")))
            {
                root = cand;
                break;
            }
        }

        Console.WriteLine("== Highlight Review · 房间明细导出 ==");
        Console.WriteLine();

        if (root == null)
        {
            Console.WriteLine("找不到项目根目录（需要 tests\\rooms_dump.lua）");
            Console.WriteLine("期望在: " + Path.Combine(toolsDir, ".."));
            Console.WriteLine("（本 exe 必须放在项目的 tools\\ 目录里）");
            Pause();
            return 2;
        }

        string luarun = Path.Combine(root, "tools", "luarun.ps1");
        string script = Path.Combine(root, "tests", "rooms_dump.lua");

        if (!File.Exists(luarun))
        {
            Console.WriteLine("找不到 luarun.ps1: " + luarun);
            Pause();
            return 2;
        }

        // 记录运行前的报告列表，跑完找新出现的那份
        string logsDir = Path.Combine(root, "_logs");
        DateTime before = DateTime.Now;

        // luarun.ps1 依赖 32 位 LuaJIT DLL，必须用 SysWOW64 的 PowerShell
        string ps32 = @"C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe";
        string psExe = File.Exists(ps32) ? ps32 : "powershell.exe";

        var psi = new ProcessStartInfo(psExe);
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + Quote(luarun) + " " + Quote(script);
        psi.UseShellExecute = false;
        psi.WorkingDirectory = root;
        if (args != null && args.Length > 0)
        {
            foreach (string a in args) { psi.Arguments += " " + Quote(a); }
        }

        Process p = Process.Start(psi);
        p.WaitForExit();

        Console.WriteLine();
        Console.WriteLine("完成（退出码 " + p.ExitCode + "）");

        string newest = NewestReport(logsDir);
        if (newest != null)
        {
            Console.WriteLine("报告: " + newest);
            try
            {
                var open = new ProcessStartInfo(newest);
                open.UseShellExecute = true;
                Process.Start(open);
            }
            catch (Exception e) { Console.WriteLine("（自动打开失败: " + e.Message + "）"); }
        }
        else
        {
            Console.WriteLine("没有找到 _logs\\rooms-*.txt");
        }

        Pause();
        return p.ExitCode;
    }

    static string NewestReport(string logsDir)
    {
        try
        {
            if (!Directory.Exists(logsDir)) return null;
            string best = null;
            DateTime bestT = DateTime.MinValue;
            foreach (string f in Directory.GetFiles(logsDir, "rooms-*.txt"))
            {
                DateTime t = File.GetLastWriteTime(f);
                if (t > bestT) { bestT = t; best = f; }
            }
            return best;
        }
        catch { return null; }
    }

    static string Quote(string s) { return "\"" + s.Replace("\"", "\\\"") + "\""; }

    static void Pause()
    {
        Console.WriteLine();
        Console.Write("按任意键关闭…");
        try { Console.ReadKey(true); } catch { }
    }
}
