using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace TechMaster {
    public static class DefaultsNative {
        [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetDefaultPrinter(StringBuilder name, ref int size);
        [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetDefaultPrinter(string name);
        public static string Printer() {
            int size=0;
            GetDefaultPrinter(null,ref size);
            if(size==0) {
                int error=Marshal.GetLastWin32Error();
                if(error==2) return String.Empty;
                throw new Win32Exception(error);
            }
            var buffer=new StringBuilder(size);
            if(!GetDefaultPrinter(buffer,ref size)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return buffer.ToString();
        }
        public static void SetPrinter(string name) {
            if(String.IsNullOrWhiteSpace(name)) throw new ArgumentException("Select a printer.");
            if(!SetDefaultPrinter(name)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        [ComImport, Guid("4e530b0a-e611-4c77-a3ac-9031d022281b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAssociationRegistration {
            [PreserveSig]
            int QueryCurrentDefault([MarshalAs(UnmanagedType.LPWStr)] string association, int type, int level,
                [MarshalAs(UnmanagedType.LPWStr)] out string progId);
        }
        public static string Association(string association, bool protocol) {
            object instance=Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("591209c7-767b-42b2-9fba-44ee4615f2c7")));
            try {
                string progId;
                int result=((IAssociationRegistration)instance).QueryCurrentDefault(association,protocol?1:0,1,out progId);
                if(result==unchecked((int)0x80070483)) return String.Empty; // no association
                Marshal.ThrowExceptionForHR(result);
                return progId??String.Empty;
            } finally {if(instance!=null) Marshal.ReleaseComObject(instance);}
        }
    }
}
