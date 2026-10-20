// Rooms 启动器：导出每局全部房间明细
// 等价于 luarun.ps1 tests\rooms_dump.lua，跑完自动打开最新报告
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class RoomsLauncher
{
    static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }
        Console.WriteLine("== Highlight Review · 房间明细导出 ==");
        Console.WriteLine();

        string root = RootFinder.Find();
        if (root == null) { Console.WriteLine("找不到项目根（需要 tests 或 mod 目录）"); RootFinder.Pause(); return 2; }

        string luarun = Path.Combine(root, "tools", "luarun.ps1");
        string script = Path.Combine(root, "tests", "rooms_dump.lua");
        if (!File.Exists(luarun)) { Console.WriteLine("找不到 " + luarun); RootFinder.Pause(); return 2; }
        if (!File.Exists(script)) { Console.WriteLine("找不到 " + script); RootFinder.Pause(); return 2; }

        // luarun.ps1 依赖 32 位 LuaJIT，必须用 SysWOW64 的 PowerShell
        string ps32 = @"C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe";
        string psExe = File.Exists(ps32) ? ps32 : "powershell.exe";

        var psi = new ProcessStartInfo(psExe);
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + RootFinder.Quote(luarun) + " " + RootFinder.Quote(script);
        psi.UseShellExecute = false;
        psi.WorkingDirectory = root;
        if (args != null) foreach (string a in args) psi.Arguments += " " + RootFinder.Quote(a);

        Process p = Process.Start(psi);
        p.WaitForExit();

        Console.WriteLine();
        Console.WriteLine("完成（退出码 " + p.ExitCode + "）");

        string newest = NewestReport(Path.Combine(root, "_logs"));
        if (newest != null)
        {
            Console.WriteLine("报告: " + newest);
            try { var o = new ProcessStartInfo(newest); o.UseShellExecute = true; Process.Start(o); }
            catch (Exception e) { Console.WriteLine("（自动打开失败: " + e.Message + "）"); }
        }
        else Console.WriteLine("没有找到 _logs\\rooms-*.txt");

        RootFinder.Pause();
        return p.ExitCode;
    }

    static string NewestReport(string logsDir)
    {
        try
        {
            if (!Directory.Exists(logsDir)) return null;
            string best = null; DateTime bestT = DateTime.MinValue;
            foreach (string f in Directory.GetFiles(logsDir, "rooms-*.txt"))
            {
                DateTime t = File.GetLastWriteTime(f);
                if (t > bestT) { bestT = t; best = f; }
            }
            return best;
        }
        catch { return null; }
    }
}