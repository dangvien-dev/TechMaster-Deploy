using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static void Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "App", "TechMaster-Deploy.ps1");
        string powerShell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");

        try
        {
            if (!File.Exists(script))
                throw new FileNotFoundException("Hãy giải nén toàn bộ gói TechMaster Deploy rồi mở lại ứng dụng.", script);

            var start = new ProcessStartInfo(powerShell)
            {
                Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\"",
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using (Process process = Process.Start(start))
            {
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "TechMaster Deploy", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
