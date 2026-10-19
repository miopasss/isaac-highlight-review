// ParseSave 启动器 —— 双击运行同目录下的 parse-save.ps1
// 编译：csc /target:exe /out:ParseSave.exe tools\ParseSaveLauncher.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class ParseSaveLauncher
{
    static int Main(string[] args)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }

        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "parse-save.ps1");

        Console.WriteLine("== Highlight Review · 存档解析 ==");
        Console.WriteLine();

        if (!File.Exists(script))
        {
            Console.WriteLine("找不到 parse-save.ps1");
            Console.WriteLine("期望位置: " + script);
            Console.WriteLine("（本 exe 必须和 parse-save.ps1 放在同一个目录里）");
            Pause();
            return 2;
        }

        // 用 -Command 而不是 -File，方便先设置控制台编码，避免中文乱码
        string extra = "";
        if (args != null && args.Length > 0)
        {
            // 只有含空格的值才加引号；否则 PowerShell 会把 "-Slot" 当成普通字符串
            foreach (string a in args) { extra += " " + (a.IndexOf(' ') >= 0 ? Quote(a) : a); }
        }

        string psCommand =
            "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; " +
            "& " + Quote(script) + extra;

        var psi = new ProcessStartInfo("powershell.exe");
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command " + Quote(psCommand);
        psi.UseShellExecute = false;

        Process p = Process.Start(psi);
        p.WaitForExit();

        Console.WriteLine();
        Console.WriteLine("解析结束（退出码 " + p.ExitCode + "）");
        Pause();
        return p.ExitCode;
    }

    static string Quote(string s)
    {
        return "\"" + s.Replace("\"", "\\\"") + "\"";
    }

    static void Pause()
    {
        Console.WriteLine();
        Console.Write("按任意键关闭…");
        try { Console.ReadKey(true); } catch { }
    }
}
