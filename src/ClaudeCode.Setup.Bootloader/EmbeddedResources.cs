using System;
using System.IO;
using System.Reflection;

namespace ClaudeCode.Setup.Bootloader
{
    /// <summary>
    /// 嵌入资源管理器 — 从程序集提取内嵌的 PowerShell 脚本和资源
    /// </summary>
    internal static class EmbeddedResources
    {
        /// <summary>
        /// 提取嵌入资源到指定目录
        /// </summary>
        /// <param name="resourceName">资源名称（如 "install.ps1"）</param>
        /// <param name="outputDir">输出目录</param>
        /// <returns>提取后的文件路径</returns>
        public static string Extract(string resourceName, string outputDir)
        {
            var assembly = Assembly.GetExecutingAssembly();
            var fullName = FindResourceName(assembly, resourceName);
            if (fullName == null)
                throw new FileNotFoundException(string.Format("嵌入资源 '{0}' 未找到", resourceName));

            var outputPath = Path.Combine(outputDir, resourceName);

            Directory.CreateDirectory(outputDir);

            using (var stream = assembly.GetManifestResourceStream(fullName))
            using (var reader = new StreamReader(stream))
            using (var writer = new StreamWriter(outputPath, false, System.Text.Encoding.UTF8))
            {
                writer.Write(reader.ReadToEnd());
            }

            return outputPath;
        }

        /// <summary>
        /// 查找嵌入资源的完整名称（忽略大小写）
        /// </summary>
        private static string FindResourceName(Assembly assembly, string targetName)
        {
            foreach (var name in assembly.GetManifestResourceNames())
            {
                if (name.EndsWith(targetName, StringComparison.OrdinalIgnoreCase))
                    return name;
            }
            return null;
        }
    }
}
