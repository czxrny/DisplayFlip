using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static void Main()
    {
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(folder, "DisplayFlip.ps1");
        try
        {
            if (!File.Exists(script))
                throw new FileNotFoundException("Keep DisplayFlip.exe together with the files from its ZIP.", script);
            ProcessStartInfo start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"",
                WorkingDirectory = folder,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using (Process process = Process.Start(start))
                process.WaitForExit();
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "DisplayFlip", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
