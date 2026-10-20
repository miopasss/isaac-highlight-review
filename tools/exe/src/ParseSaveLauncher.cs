// ParseSave 启动器：把 saveN.dat 导出成 JSON
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class ParseSaveLauncher
{
    static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }
        Console.WriteLine("== Highlight Review · 存档解析 ==");
        Console.WriteLine();

        string root = RootFinder.Find();
        if (root == null) { Console.WriteLine("找不到项目根（需要 tests 或 mod 目录）"); RootFinder.Pause(); return 2; }

        string script = Path.Combine(root, "tools", "parse-save.ps1");
        if (!File.Exists(script)) { Console.WriteLine("找不到 " + script); RootFinder.Pause(); return 2; }

        string extra = "";
        if (args != null) foreach (string a in args) extra += " " + RootFinder.Quote(a);

        var psi = new ProcessStartInfo("powershell.exe");
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + RootFinder.Quote(script) + extra;
        psi.UseShellExecute = false;
        psi.WorkingDirectory = root;

        Process p = Process.Start(psi);
        p.WaitForExit();

        Console.WriteLine();
        Console.WriteLine("完成（退出码 " + p.ExitCode + "）。结果在 _logs\\ 下。");
        RootFinder.Pause();
        return p.ExitCode;
    }
}