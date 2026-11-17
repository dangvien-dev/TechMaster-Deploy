using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace TechMaster
{
    public static class QrWindow
    {
        private delegate bool EnumCallback(IntPtr window, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumCallback callback, IntPtr parameter);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder title, int count);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool SetProp(IntPtr window, string name, IntPtr value);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetProp(IntPtr window, string name);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr RemoveProp(IntPtr window, string name);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        private static void Validate(string token)
        {
            if (token == null || !Regex.IsMatch(token, "\\A[a-f0-9]{32}\\z"))
                throw new ArgumentException("Invalid QR window token.");
        }

        private static bool Matches(IntPtr window, string token)
        {
            var title = new StringBuilder(1024);
            GetWindowText(window, title, title.Capacity);
            if (title.ToString().IndexOf("TMQR-" + token, StringComparison.Ordinal) < 0) return false;
            uint pid;
            GetWindowThreadProcessId(window, out pid);
            try
            {
                using (var process = Process.GetProcessById((int)pid))
                    return String.Equals(process.ProcessName, "chrome", StringComparison.OrdinalIgnoreCase) ||
                        String.Equals(process.ProcessName, "msedge", StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        public static long Capture(string token)
        {
            Validate(token);
            if (Environment.OSVersion.Platform != PlatformID.Win32NT) return 0;
            var found = new List<IntPtr>();
            EnumWindows(delegate(IntPtr window, IntPtr ignored)
            {
                if (Matches(window, token)) found.Add(window);
                return true;
            }, IntPtr.Zero);
            if (found.Count != 1) return 0;
            // The property is removed by Windows when this exact window dies.
            // A recycled handle or another browser tab cannot inherit ownership.
            if (!SetProp(found[0], "TechMaster.QR." + token, new IntPtr(1))) return 0;
            return found[0].ToInt64();
        }

        public static bool Close(long handle, string token)
        {
            Validate(token);
            if (Environment.OSVersion.Platform != PlatformID.Win32NT || handle == 0) return false;
            var window = new IntPtr(handle);
            string property = "TechMaster.QR." + token;
            if (GetProp(window, property) != new IntPtr(1) || !Matches(window, token)) return false;
            bool sent = PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero); // WM_CLOSE
            if (sent) RemoveProp(window, property);
            return sent;
        }
    }
}
