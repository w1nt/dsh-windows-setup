// ===========================================================================
// DeepSeek Harness - windowless launcher
//
// Why this exists
//   The supervisor (start-dsh.ps1) is a PowerShell script, so it needs a
//   console. On Windows 11 with Windows Terminal set as the default terminal
//   application, launching a console app hands the console over to Windows
//   Terminal, which opens a visible window even when the caller asked for
//   -WindowStyle Hidden. That flag maps to SW_HIDE, which hides a window that
//   already exists - but the window that appears belongs to Windows Terminal,
//   not to the console, so hiding it does nothing.
//
//   This launcher is a GUI-subsystem executable (compiled with /target:winexe),
//   so launching it creates no console at all. It then starts the supervisor
//   with CreateNoWindow = true, which asks Windows not to create a console
//   window in the first place, so Windows Terminal never gets involved.
//
//   Call chain: shortcut -> dsh-launch.exe (no console) -> powershell.exe
//   (CreateNoWindow) -> start-dsh.ps1 (the supervisor).
//
// On failure it appends the reason to logs\launcher.log AND shows a message
// box, because a silent failure with no window and no console would otherwise
// leave you with nothing to look at.
//
// ENCODING - KEEP THIS FILE PURE ASCII. It is compiled by csc.exe, but the
// project keeps every source file ASCII so no tool can mis-decode it.
// ===========================================================================

using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(baseDir, "start-dsh.ps1");

        try
        {
            if (!File.Exists(script))
            {
                throw new FileNotFoundException(
                    "start-dsh.ps1 was not found next to this launcher.", script);
            }

            string systemDir = Environment.GetFolderPath(Environment.SpecialFolder.System);
            string powershell = Path.Combine(systemDir, @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershell))
            {
                throw new FileNotFoundException("Windows PowerShell was not found.", powershell);
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = powershell;
            startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";
            startInfo.WorkingDirectory = baseDir;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;

            Process.Start(startInfo);
        }
        catch (Exception error)
        {
            ReportFailure(baseDir, error);
        }
    }

    private static void ReportFailure(string baseDir, Exception error)
    {
        string message = "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] "
            + error.GetType().Name + ": " + error.Message + Environment.NewLine;

        try
        {
            string logDir = Path.Combine(baseDir, "logs");
            Directory.CreateDirectory(logDir);
            File.AppendAllText(Path.Combine(logDir, "launcher.log"), message);
        }
        catch
        {
            // Nothing more can be done about the log.
        }

        try
        {
            MessageBox.Show(
                "DeepSeek Harness could not start." + Environment.NewLine + Environment.NewLine
                + error.Message + Environment.NewLine + Environment.NewLine
                + "Details were written to logs\\launcher.log",
                "DeepSeek Harness",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        catch
        {
            // No interactive desktop available; the log is the only record.
        }
    }
}
