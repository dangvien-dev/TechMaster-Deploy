param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$SourceOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$names = @('Update.Core.ps1', 'Update-App.ps1', 'Console.ps1', 'ConsoleFont.cs')
$encoded = @($names | ForEach-Object { '"' + [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $_))) + '"' }) -join ",`n"
$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

internal static class UpgradeHelper
{
    private static string Quote(string value) { return "'" + value.Replace("'", "''") + "'"; }

    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        try
        {
            string root;
            using (var folder = new FolderBrowserDialog())
            {
                folder.Description = "Chọn thư mục TechMaster-Deploy ĐANG DÙNG (có App và TechMaster Deploy.exe).";
                folder.SelectedPath = AppDomain.CurrentDomain.BaseDirectory;
                if (folder.ShowDialog() != DialogResult.OK) return;
                root = folder.SelectedPath;
            }
            if (!File.Exists(Path.Combine(root, "App", "TechMaster-Deploy.ps1")))
                throw new Exception("Thư mục này không có ứng dụng TechMaster Deploy.");
            string zip = null;
            string mode = "Online";
            DialogResult sourceChoice = MessageBox.Show(
                "Lấy bản mới trực tiếp từ repo dangvien-dev/TechMaster-Deploy (main)?\n\nYes: tự lấy từ repo, không cần ZIP.\nNo: chọn ZIP offline đã tải.\nCancel: thoát.",
                "Nguồn cập nhật", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (sourceChoice == DialogResult.Cancel) return;
            if (sourceChoice == DialogResult.No)
            {
                mode = "Local";
                using (var pick = new OpenFileDialog())
                {
                    pick.Title = "Chọn ZIP phiên bản TechMaster Deploy vừa tải (không cần giải nén)";
                    pick.Filter = "TechMaster Deploy ZIP (*.zip)|*.zip";
                    if (pick.ShowDialog() != DialogResult.OK) return;
                    zip = pick.FileName;
                }
            }
            if (MessageBox.Show("Đóng TechMaster và các cửa sổ công cụ đang chạy trước khi tiếp tục. Công cụ sẽ kiểm tra gói, sao lưu và hỏi xác nhận trước khi cài.",
                "Nâng cấp TechMaster Deploy", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
            string runner = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TechMaster Deploy", "Update Runner", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(runner);
            string[] names = { "Update.Core.ps1", "Update-App.ps1", "Console.ps1", "ConsoleFont.cs" };
            string[] data = { __EMBEDDED_FILES__ };
            for (int i = 0; i < names.Length; i++)
                File.WriteAllBytes(Path.Combine(runner, names[i]), Convert.FromBase64String(data[i]));
            string command = "& " + Quote(Path.Combine(runner, "Update-App.ps1")) + " -Root " + Quote(root) + " -Mode " + mode;
            if (zip != null) command += " -PackagePath " + Quote(zip);
            string systemPowerShell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            var start = new ProcessStartInfo(systemPowerShell)
            {
                Arguments = "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(command)),
                WorkingDirectory = runner,
                UseShellExecute = false,
                CreateNoWindow = false
            };
            using (Process p = Process.Start(start)) { }
        }
        catch (Exception error) { MessageBox.Show(error.Message, "TechMaster Update", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
}
'@
$source = $source.Replace('__EMBEDDED_FILES__', $encoded)
$sourcePath = Join-Path $OutputDirectory 'UpgradeHelper.cs'
[IO.File]::WriteAllText($sourcePath, $source, [Text.UTF8Encoding]::new($true))
if ($SourceOnly) { Write-Output $sourcePath; return }
$framework = if ([Environment]::Is64BitOperatingSystem) { 'Framework64' } else { 'Framework' }
$compiler = Join-Path $env:WINDIR "Microsoft.NET/$framework/v4.0.30319/csc.exe"
$exe = Join-Path $OutputDirectory 'TechMaster Update.exe'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 "/out:$exe" "/win32icon:$(Join-Path $PSScriptRoot 'TechMaster.ico')" "/win32manifest:$(Join-Path $PSScriptRoot 'Launcher.manifest')" /reference:System.Windows.Forms.dll $sourcePath
if ($LASTEXITCODE -ne 0) { throw 'Build công cụ nâng cấp thất bại.' }
Write-Output $exe
