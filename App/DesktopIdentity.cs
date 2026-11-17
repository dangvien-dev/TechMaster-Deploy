using System;
using System.Runtime.InteropServices;
namespace TechMaster {
    public static class DesktopIdentity {
        [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string id);
        [DllImport("shell32.dll")]
        private static extern int GetCurrentProcessExplicitAppUserModelID(out IntPtr id);
        public static void Initialize() {
            if (Environment.OSVersion.Platform == PlatformID.Win32NT)
                Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID("TechMaster.Deploy"));
        }
        [DllImport("user32.dll")]
        private static extern bool ShowWindowAsync(IntPtr window, int command);
        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr window);
        public static bool ActivateWindow(IntPtr window) {
            if (window == IntPtr.Zero) return false;
            ShowWindowAsync(window, IsIconic(window) ? 9 : 5);
            return SetForegroundWindow(window);
        }
        public static string CurrentId() {
            if (Environment.OSVersion.Platform != PlatformID.Win32NT) return "";
            IntPtr value;
            Marshal.ThrowExceptionForHR(GetCurrentProcessExplicitAppUserModelID(out value));
            try { return Marshal.PtrToStringUni(value); } finally { Marshal.FreeCoTaskMem(value); }
        }
    }
}
