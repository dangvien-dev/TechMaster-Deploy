using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security;
namespace TechMaster {
    // Saved Windows credentials for a file server (Credential Manager) and a connection test that stores nothing.
    public static class LanConnectNative {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        private struct CREDENTIAL {
            public int Flags;
            public int Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public int CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int Persist;
            public int AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        private struct NETRESOURCE {
            public int Scope;
            public int Type;
            public int DisplayType;
            public int Usage;
            public string LocalName;
            public string RemoteName;
            public string Comment;
            public string Provider;
        }
        private const int CRED_TYPE_DOMAIN_PASSWORD=2;
        private const int CRED_PERSIST_LOCAL_MACHINE=2;
        private const int ERROR_NOT_FOUND=1168;
        private const int RESOURCETYPE_ANY=0;
        private const int RESOURCETYPE_DISK=1;
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CredWriteW(ref CREDENTIAL credential, int flags);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CredReadW(string target, int type, int flags, out IntPtr credential);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CredDeleteW(string target, int type, int flags);
        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr buffer);
        [DllImport("mpr.dll", CharSet=CharSet.Unicode)]
        private static extern int WNetAddConnection2W(ref NETRESOURCE resource, IntPtr password, string userName, int flags);
        [DllImport("mpr.dll", CharSet=CharSet.Unicode)]
        private static extern int WNetCancelConnection2W(string name, int flags, [MarshalAs(UnmanagedType.Bool)] bool force);

        // Connects with the given account without saving anything, then disconnects. Returns the Win32 error code (0 = success).
        public static int TestConnection(string unc, string userName, SecureString password) {
            return TestConnection(unc, userName, password, RESOURCETYPE_DISK);
        }
        // resourceType 0 (RESOURCETYPE_ANY) with \\server\IPC$ checks the account on a computer that only shares printers.
        public static int TestConnection(string unc, string userName, SecureString password, int resourceType) {
            if(String.IsNullOrWhiteSpace(unc) || !unc.StartsWith(@"\\")) throw new ArgumentException("UNC path required.");
            if(password==null || password.Length==0) throw new ArgumentException("Password required.");
            if(resourceType!=RESOURCETYPE_ANY && resourceType!=RESOURCETYPE_DISK) throw new ArgumentException("Resource type must be any or disk.");
            var resource=new NETRESOURCE();
            resource.Type=resourceType;
            resource.RemoteName=unc;
            IntPtr secret=Marshal.SecureStringToGlobalAllocUnicode(password);
            try {
                int result=WNetAddConnection2W(ref resource, secret, userName, 0);
                if(result==0) WNetCancelConnection2W(unc, 0, true);
                return result;
            } finally {Marshal.ZeroFreeGlobalAllocUnicode(secret);}
        }
        // Same as cmdkey /add:<server> /user:<user>, without putting the password on a command line.
        public static void SavePassword(string server, string userName, SecureString password) {
            if(String.IsNullOrWhiteSpace(server) || String.IsNullOrWhiteSpace(userName)) throw new ArgumentException("Server and user required.");
            if(password==null || password.Length==0) throw new ArgumentException("Password required.");
            IntPtr secret=Marshal.SecureStringToGlobalAllocUnicode(password);
            try {
                var credential=new CREDENTIAL();
                credential.Type=CRED_TYPE_DOMAIN_PASSWORD;
                credential.TargetName=server;
                credential.UserName=userName;
                credential.Comment="TechMaster LAN";
                credential.CredentialBlob=secret;
                credential.CredentialBlobSize=password.Length*2;
                credential.Persist=CRED_PERSIST_LOCAL_MACHINE;
                if(!CredWriteW(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
            } finally {Marshal.ZeroFreeGlobalAllocUnicode(secret);}
        }
        // User name saved for the server, or null. The password itself cannot be read back.
        public static string SavedUser(string server) {
            IntPtr pointer;
            if(!CredReadW(server, CRED_TYPE_DOMAIN_PASSWORD, 0, out pointer)) {
                int error=Marshal.GetLastWin32Error();
                if(error==ERROR_NOT_FOUND) return null;
                throw new Win32Exception(error);
            }
            try {
                var credential=(CREDENTIAL)Marshal.PtrToStructure(pointer, typeof(CREDENTIAL));
                return credential.UserName??String.Empty;
            } finally {CredFree(pointer);}
        }
        public static bool DeletePassword(string server) {
            if(CredDeleteW(server, CRED_TYPE_DOMAIN_PASSWORD, 0)) return true;
            int error=Marshal.GetLastWin32Error();
            if(error==ERROR_NOT_FOUND) return false;
            throw new Win32Exception(error);
        }
    }
}
