using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Principal;
namespace TechMaster {
    // Logon rights (LSA), local group membership by SID and password comparison without plain-text strings.
    public static class LanAccountsNative {
        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_UNICODE_STRING {
            public ushort Length;
            public ushort MaximumLength;
            public IntPtr Buffer;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_OBJECT_ATTRIBUTES {
            public int Length;
            public IntPtr RootDirectory;
            public IntPtr ObjectName;
            public int Attributes;
            public IntPtr SecurityDescriptor;
            public IntPtr SecurityQualityOfService;
        }
        private const int POLICY_CREATE_ACCOUNT=0x10;
        private const int POLICY_LOOKUP_NAMES=0x800;
        private const uint STATUS_OBJECT_NAME_NOT_FOUND=0xC0000034;
        [DllImport("advapi32.dll")]
        private static extern uint LsaOpenPolicy(IntPtr systemName, ref LSA_OBJECT_ATTRIBUTES attributes, int access, out IntPtr policy);
        [DllImport("advapi32.dll")]
        private static extern uint LsaAddAccountRights(IntPtr policy, byte[] sid, LSA_UNICODE_STRING[] rights, int count);
        [DllImport("advapi32.dll")]
        private static extern uint LsaRemoveAccountRights(IntPtr policy, byte[] sid, [MarshalAs(UnmanagedType.U1)] bool allRights, LSA_UNICODE_STRING[] rights, int count);
        [DllImport("advapi32.dll")]
        private static extern uint LsaEnumerateAccountRights(IntPtr policy, byte[] sid, out IntPtr rights, out int count);
        [DllImport("advapi32.dll")]
        private static extern uint LsaFreeMemory(IntPtr buffer);
        [DllImport("advapi32.dll")]
        private static extern uint LsaClose(IntPtr policy);
        [DllImport("advapi32.dll")]
        private static extern int LsaNtStatusToWinError(uint status);
        [DllImport("netapi32.dll", CharSet=CharSet.Unicode)]
        private static extern int NetUserGetLocalGroups(string server, string user, int level, int flags, out IntPtr buffer, int preferredMaximum, out int entriesRead, out int totalEntries);
        [DllImport("netapi32.dll")]
        private static extern int NetApiBufferFree(IntPtr buffer);

        private static byte[] SidBytes(string sid) {
            var identifier=new SecurityIdentifier(sid);
            var bytes=new byte[identifier.BinaryLength];
            identifier.GetBinaryForm(bytes, 0);
            return bytes;
        }
        private static IntPtr OpenPolicy() {
            var attributes=new LSA_OBJECT_ATTRIBUTES();
            attributes.Length=Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
            IntPtr policy;
            uint status=LsaOpenPolicy(IntPtr.Zero, ref attributes, POLICY_CREATE_ACCOUNT|POLICY_LOOKUP_NAMES, out policy);
            if(status!=0) throw new Win32Exception(LsaNtStatusToWinError(status));
            return policy;
        }
        private static LSA_UNICODE_STRING[] Strings(string[] values, List<IntPtr> allocated) {
            var result=new LSA_UNICODE_STRING[values.Length];
            for(int i=0;i<values.Length;i++) {
                IntPtr buffer=Marshal.StringToHGlobalUni(values[i]);
                allocated.Add(buffer);
                result[i].Buffer=buffer;
                result[i].Length=(ushort)(values[i].Length*2);
                result[i].MaximumLength=(ushort)(values[i].Length*2+2);
            }
            return result;
        }
        public static string[] GetRights(string sid) {
            IntPtr policy=OpenPolicy();
            try {
                IntPtr buffer; int count;
                uint status=LsaEnumerateAccountRights(policy, SidBytes(sid), out buffer, out count);
                if(status==STATUS_OBJECT_NAME_NOT_FOUND) return new string[0];
                if(status!=0) throw new Win32Exception(LsaNtStatusToWinError(status));
                try {
                    var rights=new string[count];
                    int size=Marshal.SizeOf(typeof(LSA_UNICODE_STRING));
                    for(int i=0;i<count;i++) {
                        var value=(LSA_UNICODE_STRING)Marshal.PtrToStructure(new IntPtr(buffer.ToInt64()+(long)i*size), typeof(LSA_UNICODE_STRING));
                        rights[i]=Marshal.PtrToStringUni(value.Buffer, value.Length/2);
                    }
                    return rights;
                } finally {LsaFreeMemory(buffer);}
            } finally {LsaClose(policy);}
        }
        public static void AddRights(string sid, string[] rights) {
            if(rights==null || rights.Length==0) return;
            var allocated=new List<IntPtr>();
            IntPtr policy=OpenPolicy();
            try {
                uint status=LsaAddAccountRights(policy, SidBytes(sid), Strings(rights, allocated), rights.Length);
                if(status!=0) throw new Win32Exception(LsaNtStatusToWinError(status));
            } finally {
                LsaClose(policy);
                foreach(IntPtr buffer in allocated) Marshal.FreeHGlobal(buffer);
            }
        }
        // Used only to undo a half-created account: removes every right recorded for the SID.
        public static void RemoveAllRights(string sid) {
            IntPtr policy=OpenPolicy();
            try {
                uint status=LsaRemoveAccountRights(policy, SidBytes(sid), true, null, 0);
                if(status!=0 && status!=STATUS_OBJECT_NAME_NOT_FOUND) throw new Win32Exception(LsaNtStatusToWinError(status));
            } finally {LsaClose(policy);}
        }
        // SIDs of the local groups a local user belongs to (directly or indirectly); names differ by Windows language.
        public static string[] LocalGroupSids(string userName) {
            IntPtr buffer; int read, total;
            int result=NetUserGetLocalGroups(null, userName, 0, 1, out buffer, -1, out read, out total);
            if(result!=0) throw new Win32Exception(result);
            var sids=new List<string>();
            try {
                for(int i=0;i<read;i++) {
                    IntPtr namePointer=Marshal.ReadIntPtr(new IntPtr(buffer.ToInt64()+(long)i*IntPtr.Size));
                    string name=Marshal.PtrToStringUni(namePointer);
                    try {sids.Add(new NTAccount(name).Translate(typeof(SecurityIdentifier)).Value);}
                    catch(IdentityNotMappedException) {}
                }
            } finally {NetApiBufferFree(buffer);}
            return sids.ToArray();
        }
        public static bool SecureEquals(SecureString first, SecureString second) {
            if(first==null || second==null || first.Length!=second.Length) return false;
            IntPtr a=IntPtr.Zero, b=IntPtr.Zero;
            try {
                a=Marshal.SecureStringToGlobalAllocUnicode(first);
                b=Marshal.SecureStringToGlobalAllocUnicode(second);
                int difference=0;
                for(int i=0;i<first.Length*2;i++) difference|=Marshal.ReadByte(a, i)^Marshal.ReadByte(b, i);
                return difference==0;
            } finally {
                if(a!=IntPtr.Zero) Marshal.ZeroFreeGlobalAllocUnicode(a);
                if(b!=IntPtr.Zero) Marshal.ZeroFreeGlobalAllocUnicode(b);
            }
        }
    }
}
