using System;
using System.Runtime.InteropServices;

namespace TechMaster
{
    public static class ConsoleFont
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FontInfo
        {
            public uint Size;
            public uint Index;
            public short Width;
            public short Height;
            public uint Family;
            public uint Weight;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string FaceName;
        }

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetStdHandle(int standardHandle);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetCurrentConsoleFontEx(IntPtr output,
            [MarshalAs(UnmanagedType.Bool)] bool maximum, ref FontInfo font);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetCurrentConsoleFontEx(IntPtr output,
            [MarshalAs(UnmanagedType.Bool)] bool maximum, ref FontInfo font);

        public static bool UseVietnameseFont()
        {
            IntPtr output = GetStdHandle(-11);
            if (output == IntPtr.Zero || output == new IntPtr(-1))
                return false;

            FontInfo font = new FontInfo { Size = (uint)Marshal.SizeOf(typeof(FontInfo)) };
            if (!GetCurrentConsoleFontEx(output, false, ref font))
                return false; // Redirected output or a host that owns its own font.

            if (String.Equals(font.FaceName, "Consolas", StringComparison.OrdinalIgnoreCase))
                return true;

            // Other TrueType fonts, including Lucida Console, may lack Vietnamese
            // glyphs too. Prefer Consolas for all classic console windows, while
            // retaining the user's current character height.
            font.Index = 0;
            font.Width = 0;
            if (font.Height <= 0) font.Height = 16;
            font.Family = 0x36;
            font.Weight = 400;
            font.FaceName = "Consolas";
            return SetCurrentConsoleFontEx(output, false, ref font);
        }
    }
}
