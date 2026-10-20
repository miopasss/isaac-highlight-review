// Book 启动器：跑 tools\book.ps1 生成册子
// 编译见 tools\exe\build.ps1
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class BookLauncher
{
    static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }
        Console.WriteLine("== Highlight Review · 生成册子 ==");
        Console.WriteLine();

        string root = RootFinder.Find();
        if (root == null) { Console.WriteLine("找不到项目根（需要 tests 或 mod 目录）"); RootFinder.Pause(); return 2; }

        string script = Path.Combine(root, "tools", "book.ps1");
        if (!File.Exists(script)) { Console.WriteLine("找不到 " + script); RootFinder.Pause(); return 2; }

        string extra = "";
        if (args != null) foreach (string a in args) extra += " " + RootFinder.Quote(a);

        var psi = new ProcessStartInfo("powershell.exe");
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + RootFinder.Quote(script) + " -Open" + extra;
        psi.UseShellExecute = false;
        psi.WorkingDirectory = root;

        Process p = Process.Start(psi);
        p.WaitForExit();

        Console.WriteLine();
        Console.WriteLine("完成（退出码 " + p.ExitCode + "）。报告在 _logs\\ 下。");
        RootFinder.Pause();
        return p.ExitCode;
    }
}