using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace TechMaster {
    // Read-only device listing (present and non-present) plus removal of non-present device nodes.
    // Removal never touches a connected device and never deletes driver packages.
    public sealed class DeviceNode {
        public string InstanceId { get; set; }
        public string Class { get; set; }
        public string FriendlyName { get; set; }
        public string ContainerId { get; set; }
        public string Parent { get; set; }
        public bool Present { get; set; }
    }
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

        [StructLayout(LayoutKind.Sequential)]
        private struct SP_DEVINFO_DATA {
            public int cbSize;
            public Guid ClassGuid;
            public int DevInst;
            public IntPtr Reserved;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct DEVPROPKEY {
            public Guid fmtid;
            public int pid;
            public DEVPROPKEY(Guid f,int p) {fmtid=f;pid=p;}
        }
        private const int DIGCF_ALLCLASSES=0x4;          // without DIGCF_PRESENT: present and non-present devices
        private const int CM_LOCATE_DEVNODE_NORMAL=0x0;  // present devices only
        private const int CM_LOCATE_DEVNODE_PHANTOM=0x1; // present or non-present
        private const int CR_SUCCESS=0x0;
        private const int CR_NO_SUCH_DEVNODE=0xD;
        private static readonly IntPtr InvalidHandle=new IntPtr(-1);
        private static readonly Guid DeviceProperties=new Guid("a45c254e-df1c-4efd-8020-67d146a850e0");
        private static readonly DEVPROPKEY DescriptionKey=new DEVPROPKEY(DeviceProperties,2);
        private static readonly DEVPROPKEY ClassKey=new DEVPROPKEY(DeviceProperties,9);
        private static readonly DEVPROPKEY FriendlyNameKey=new DEVPROPKEY(DeviceProperties,14);
        private static readonly DEVPROPKEY ParentKey=new DEVPROPKEY(new Guid("4340a6c5-93fa-4706-972c-7b648008a5a7"),8);
        private static readonly DEVPROPKEY ContainerKey=new DEVPROPKEY(new Guid("8c7ed206-3f8a-4827-b3ab-ae9e1faefc6c"),2);

        [DllImport("setupapi.dll", SetLastError=true)]
        private static extern IntPtr SetupDiGetClassDevsW(IntPtr classGuid, IntPtr enumerator, IntPtr parent, int flags);
        [DllImport("setupapi.dll", SetLastError=true)]
        private static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr classGuid, IntPtr parent);
        [DllImport("setupapi.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiEnumDeviceInfo(IntPtr set, int index, ref SP_DEVINFO_DATA data);
        [DllImport("setupapi.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiGetDeviceInstanceIdW(IntPtr set, ref SP_DEVINFO_DATA data, StringBuilder id, int size, ref int required);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiGetDevicePropertyW(IntPtr set, ref SP_DEVINFO_DATA data, ref DEVPROPKEY key, ref int type, byte[] buffer, int size, ref int required, int flags);
        [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiOpenDeviceInfoW(IntPtr set, string instanceId, IntPtr parent, int flags, ref SP_DEVINFO_DATA data);
        [DllImport("setupapi.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiRemoveDevice(IntPtr set, ref SP_DEVINFO_DATA data);
        [DllImport("cfgmgr32.dll")]
        private static extern int CM_Get_DevNode_Status(ref int status, ref int problem, int devInst, int flags);
        [DllImport("cfgmgr32.dll", CharSet=CharSet.Unicode)]
        private static extern int CM_Locate_DevNodeW(ref int devInst, string deviceId, int flags);
        [DllImport("cfgmgr32.dll")]
        private static extern int CM_Uninstall_DevNode(int devInst, int flags);

        private static byte[] Property(IntPtr set, ref SP_DEVINFO_DATA data, DEVPROPKEY key) {
            int type=0, needed=0;
            SetupDiGetDevicePropertyW(set, ref data, ref key, ref type, null, 0, ref needed, 0);
            if(needed<=0) return null;
            var buffer=new byte[needed];
            if(!SetupDiGetDevicePropertyW(set, ref data, ref key, ref type, buffer, buffer.Length, ref needed, 0)) return null;
            return buffer;
        }
        private static string StringProperty(IntPtr set, ref SP_DEVINFO_DATA data, DEVPROPKEY key) {
            byte[] value=Property(set, ref data, key);
            return value==null ? String.Empty : Encoding.Unicode.GetString(value).TrimEnd('\0');
        }
        private static string GuidProperty(IntPtr set, ref SP_DEVINFO_DATA data, DEVPROPKEY key) {
            byte[] value=Property(set, ref data, key);
            return (value!=null && value.Length==16) ? new Guid(value).ToString() : String.Empty;
        }
        private static bool IsPresent(int devInst) {
            int status=0, problem=0;
            return CM_Get_DevNode_Status(ref status, ref problem, devInst, 0)==CR_SUCCESS;
        }
        public static DeviceNode[] Devices() {
            IntPtr set=SetupDiGetClassDevsW(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, DIGCF_ALLCLASSES);
            if(set==InvalidHandle) throw new Win32Exception(Marshal.GetLastWin32Error());
            var nodes=new List<DeviceNode>();
            try {
                var data=new SP_DEVINFO_DATA();
                data.cbSize=Marshal.SizeOf(typeof(SP_DEVINFO_DATA));
                for(int index=0; SetupDiEnumDeviceInfo(set, index, ref data); index++) {
                    var id=new StringBuilder(1024);
                    int needed=0;
                    if(!SetupDiGetDeviceInstanceIdW(set, ref data, id, id.Capacity, ref needed)) continue;
                    var node=new DeviceNode();
                    node.InstanceId=id.ToString();
                    node.Present=IsPresent(data.DevInst);
                    node.Class=StringProperty(set, ref data, ClassKey);
                    node.FriendlyName=StringProperty(set, ref data, FriendlyNameKey);
                    if(String.IsNullOrEmpty(node.FriendlyName)) node.FriendlyName=StringProperty(set, ref data, DescriptionKey);
                    node.Parent=StringProperty(set, ref data, ParentKey);
                    node.ContainerId=GuidProperty(set, ref data, ContainerKey);
                    nodes.Add(node);
                }
            } finally {SetupDiDestroyDeviceInfoList(set);}
            return nodes.ToArray();
        }
        // Returns true when removed, false when the device node no longer exists.
        public static bool RemovePhantomDevice(string instanceId) {
            if(String.IsNullOrWhiteSpace(instanceId)) throw new ArgumentException("Device instance ID is empty.");
            int devInst=0;
            if(CM_Locate_DevNodeW(ref devInst, instanceId, CM_LOCATE_DEVNODE_NORMAL)==CR_SUCCESS) throw new InvalidOperationException("Device is connected; not removed: "+instanceId);
            int located=CM_Locate_DevNodeW(ref devInst, instanceId, CM_LOCATE_DEVNODE_PHANTOM);
            if(located==CR_NO_SUCH_DEVNODE) return false;
            if(located!=CR_SUCCESS) throw new InvalidOperationException(String.Format("CM_Locate_DevNode 0x{0:X}: {1}", located, instanceId));
            if(IsPresent(devInst)) throw new InvalidOperationException("Device is connected; not removed: "+instanceId);
            int uninstalled=CM_Uninstall_DevNode(devInst, 0);
            if(uninstalled==CR_SUCCESS) return true;
            IntPtr set=SetupDiCreateDeviceInfoList(IntPtr.Zero, IntPtr.Zero);
            if(set==InvalidHandle) throw new InvalidOperationException(String.Format("CM_Uninstall_DevNode 0x{0:X}: {1}", uninstalled, instanceId));
            try {
                var data=new SP_DEVINFO_DATA();
                data.cbSize=Marshal.SizeOf(typeof(SP_DEVINFO_DATA));
                if(SetupDiOpenDeviceInfoW(set, instanceId, IntPtr.Zero, 0, ref data) && SetupDiRemoveDevice(set, ref data)) return true;
                int error=Marshal.GetLastWin32Error();
                throw new InvalidOperationException(String.Format("CM_Uninstall_DevNode 0x{0:X}, SetupDiRemoveDevice {1}: {2}", uninstalled, error, instanceId));
            } finally {SetupDiDestroyDeviceInfoList(set);}
        }
    }
}
