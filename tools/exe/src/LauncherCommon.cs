// 三个启动器共用的项目根定位逻辑。
// 本文件不单独编译，被 Book/ParseSave/Rooms 三个 .cs 直接 include（用 /out 一起编译）。
//
// 目录结构（2026-10 重排后）：
//   <root>\tools\exe\<name>.exe      ← 本 exe 所在
//   <root>\tools\exe\src\*.cs        ← 源码
//   <root>\tools\*.ps1               ← PowerShell 脚本
//   <root>\tests\*.lua               ← 离线测试
//
// 所以本 exe 要上溯 3 层才是项目根。
using System;
using System.IO;

static class RootFinder
{
    /// <summary>从 exe 所在目录向上找，直到发现 tests 或 mod 目录</summary>
    public static string Find()
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        for (int i = 0; i < 5; i++)
        {
            if (DirExists(dir, "tests") || DirExists(dir, "mod"))
                return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        return null;
    }

    static bool DirExists(string root, string name)
    {
        try { return Directory.Exists(Path.Combine(root, name)); }
        catch { return false; }
    }

    public static string Quote(string s)
    {
        return "\"" + s.Replace("\"", "\\\"") + "\"";
    }

    public static void Pause()
    {
        Console.WriteLine();
        Console.Write("按任意键关闭…");
        try { Console.ReadKey(true); } catch { }
    }
}
