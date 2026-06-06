using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

namespace ClaudeCode.Setup.Bootloader
{
    /// <summary>
    /// ClaudeCode 一键环境配置器 — 原生启动器
    /// 负责：UAC 提权 → 解压内嵌脚本和模块 → 启动 PowerShell 执行 → 实时输出转发
    /// </summary>
    internal class Program
    {
        private const string ScriptName = "install.ps1";
        private const string TempDirName = "claudecode-setup";
        private static readonly string[] CoreModules = { "Config.psm1", "Logger.psm1", "Downloader.psm1", "Progress.psm1" };
        private static readonly string[] FuncModules = { "SystemCheck.psm1", "NodeInstaller.psm1", "NpmConfig.psm1",
            "CcSwitchInstaller.psm1", "EnvironmentManager.psm1", "Uninstaller.psm1", "Validator.psm1" };

        static int Main(string[] args)
        {
            Console.Title = "ClaudeCode 一键环境配置器";

            try
            {
                // 1. 检查是否以管理员运行
                if (!IsAdministrator())
                {
                    Console.ForegroundColor = ConsoleColor.Yellow;
                    Console.WriteLine("需要管理员权限，正在请求提权...");
                    Console.ResetColor();

                    // 以管理员权限重新启动自身
                    var startInfo = new ProcessStartInfo
                    {
                        FileName = Process.GetCurrentProcess().MainModule.FileName,
                        UseShellExecute = true,
                        Verb = "runas",
                        Arguments = string.Join(" ", args)
                    };

                    try
                    {
                        using (var process = Process.Start(startInfo))
                        {
                            if (process != null)
                            {
                                process.WaitForExit();
                                return process.ExitCode;
                            }
                            return 1;
                        }
                    }
                    catch
                    {
                        Console.ForegroundColor = ConsoleColor.Red;
                        Console.WriteLine("提权失败 — 请右键 → 以管理员身份运行此程序");
                        Console.ResetColor();
                        Console.WriteLine("按任意键退出...");
                        Console.ReadKey();
                        return 1;
                    }
                }

                // 2. 显示菜单（交互模式）
                string extraArgs = "";
                if (args.Length == 0)
                {
                    Console.ForegroundColor = ConsoleColor.Cyan;
                    Console.WriteLine("============================================");
                    Console.WriteLine("  ClaudeCode 一键环境配置器");
                    Console.WriteLine("============================================");
                    Console.ResetColor();
                    Console.WriteLine();
                    Console.WriteLine("  1. 安装 ClaudeCode 环境");
                    Console.WriteLine("  2. 卸载清理");
                    Console.WriteLine();
                    Console.Write("  请选择 (1/2): ");
                    var key = Console.ReadKey();
                    Console.WriteLine();
                    Console.WriteLine();

                    if (key.KeyChar == '2')
                        extraArgs = "-Uninstall -All";
                    // 1 或其他键 -> 安装模式，传 -Unattended
                }

                // 3. 创建临时目录并提取所有脚本和模块
                var tempDir = Path.Combine(Path.GetTempPath(), TempDirName);
                CleanupTempDir(tempDir);

                Console.ForegroundColor = ConsoleColor.Cyan;
                Console.WriteLine("正在准备安装环境...");
                Console.ResetColor();

                // 提取主脚本
                var scriptPath = EmbeddedResources.Extract(ScriptName, tempDir);

                // 提取核心模块到 core/ 子目录
                var coreDir = Path.Combine(tempDir, "core");
                foreach (var mod in CoreModules)
                    EmbeddedResources.Extract(mod, coreDir);

                // 提取功能模块到 modules/ 子目录
                var modulesDir = Path.Combine(tempDir, "modules");
                foreach (var mod in FuncModules)
                    EmbeddedResources.Extract(mod, modulesDir);

                // 提取 banner
                EmbeddedResources.Extract("banner.txt", tempDir);

                // 可选：提取内嵌的 cc-switch zip（不存在则运行时下载）
                try {
                    EmbeddedResources.Extract("cc-switch-portable.zip", tempDir);
                }
                catch {
                    // zip 未内嵌，运行时下载
                }

                // 3. 启动 PowerShell 执行安装脚本
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Unattended {1} {2}", scriptPath, extraArgs, string.Join(" ", args)),
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    WorkingDirectory = tempDir
                };

                using (var process = new Process { StartInfo = psi })
                {
                    // 实时转发输出（带颜色）
                    process.OutputDataReceived += (sender, e) =>
                    {
                        if (e.Data != null)
                            ForwardColoredOutput(e.Data);
                    };
                    process.ErrorDataReceived += (sender, e) =>
                    {
                        if (e.Data != null)
                        {
                            Console.ForegroundColor = ConsoleColor.Red;
                            Console.WriteLine(e.Data);
                            Console.ResetColor();
                        }
                    };

                    process.Start();
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    process.WaitForExit();

                    // 4. 传递退出码
                    if (process.ExitCode != 0)
                    {
                        Console.ForegroundColor = ConsoleColor.Red;
                        Console.WriteLine(string.Format("\n安装过程中断 (退出码: {0})", process.ExitCode));
                        Console.ResetColor();
                        Console.WriteLine("按任意键退出...");
                        Console.ReadKey();
                        return process.ExitCode;
                    }
                }

                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("\n按任意键退出...");
                Console.ResetColor();
                Console.ReadKey();
                return 0;
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine(string.Format("\n发生错误: {0}", ex.Message));
                Console.ResetColor();
                Console.WriteLine("按任意键退出...");
                Console.ReadKey();
                return 1;
            }
        }

        /// <summary>
        /// 检查当前进程是否以管理员权限运行
        /// </summary>
        private static bool IsAdministrator()
        {
            using (var identity = System.Security.Principal.WindowsIdentity.GetCurrent())
            {
                var principal = new System.Security.Principal.WindowsPrincipal(identity);
                return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
            }
        }

        /// <summary>
        /// 清理临时目录（幂等安全）
        /// </summary>
        private static void CleanupTempDir(string dir)
        {
            try
            {
                if (Directory.Exists(dir))
                    Directory.Delete(dir, recursive: true);
            }
            catch
            {
                // 删除失败不影响主流程
            }
        }

        /// <summary>
        /// 根据输出内容自动匹配颜色并转发到控制台
        /// 支持 PowerShell 彩色日志的标签解析
        /// </summary>
        private static void ForwardColoredOutput(string line)
        {
            if (string.IsNullOrEmpty(line))
            {
                Console.WriteLine();
                return;
            }

            // 根据标签着色
            if (line.Contains("[ERROR]"))
                Console.ForegroundColor = ConsoleColor.Red;
            else if (line.Contains("[WARN]"))
                Console.ForegroundColor = ConsoleColor.Yellow;
            else if (line.Contains("[OK]"))
                Console.ForegroundColor = ConsoleColor.Green;
            else if (line.Contains("[INFO]"))
                Console.ForegroundColor = ConsoleColor.Cyan;
            else if (line.Contains("[STEP]"))
                Console.ForegroundColor = ConsoleColor.Magenta;
            else if (line.Contains("[....]"))
                Console.ForegroundColor = ConsoleColor.DarkGray;
            else
                Console.ForegroundColor = ConsoleColor.Gray;

            Console.WriteLine(line);
            Console.ResetColor();
        }
    }
}
