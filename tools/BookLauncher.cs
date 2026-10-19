// Book 启动器 —— 双击运行同目录下的 book.ps1（生成册子）
// 编译：csc /target:exe /out:Book.exe tools\BookLauncher.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class BookLauncher
{
    static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }

        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "book.ps1");

        Console.WriteLine("== Highlight Review · 生成册子 ==");
        Console.WriteLine();

        if (!File.Exists(script))
        {
            Console.WriteLine("找不到 book.ps1");
            Console.WriteLine("期望位置: " + script);
            Console.WriteLine("（本 exe 必须和 book.ps1 放在同一个目录里）");
            Pause();
            return 2;
        }

        string extra = "";
        if (args != null && args.Length > 0)
        {
            foreach (string a in args) { extra += " " + (a.IndexOf(' ') >= 0 ? Quote(a) : a); }
        }

        var psi = new ProcessStartInfo("powershell.exe");
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + Quote(script) + extra;
        psi.UseShellExecute = false;

        Process p = Process.Start(psi);
        p.WaitForExit();

        Console.WriteLine();
        Console.WriteLine("完成（退出码 " + p.ExitCode + "）");
        Console.WriteLine("报告在 _logs\\ 目录下（book-*.txt）");
        Pause();
        return p.ExitCode;
    }

    static string Quote(string s) { return "\"" + s.Replace("\"", "\\\"") + "\""; }

    static void Pause()
    {
        Console.WriteLine();
        Console.Write("按任意键关闭…");
        try { Console.ReadKey(true); } catch { }
    }
}
