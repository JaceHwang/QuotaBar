using System;
using System.Runtime.InteropServices;
using System.Text;

namespace QuotaBar.Windows;
internal enum BarkSecretState { Missing,Available,Unavailable }
internal readonly record struct BarkSecretResult(BarkSecretState State,string? Key=null);
internal interface IBarkSecretStore {
    BarkSecretResult Read();
    bool Write(string key);
    bool Clear();
}
// Generic credentials are scoped to the current Windows user. No plaintext fallback.
internal sealed class BarkSecretStore : IBarkSecretStore {
    const string Target="QuotaBar/Bark/DeviceKey";
    const int NotFound=1168;
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    struct Credential {
        public uint Flags,Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist,AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias,UserName;
    }
    [DllImport("advapi32.dll",EntryPoint="CredReadW",CharSet=CharSet.Unicode,SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)] static extern bool CredRead(string target,uint type,uint flags,out IntPtr credential);
    [DllImport("advapi32.dll",EntryPoint="CredWriteW",CharSet=CharSet.Unicode,SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)] static extern bool CredWrite(ref Credential credential,uint flags);
    [DllImport("advapi32.dll",EntryPoint="CredDeleteW",CharSet=CharSet.Unicode,SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)] static extern bool CredDelete(string target,uint type,uint flags);
    [DllImport("advapi32.dll")] static extern void CredFree(IntPtr credential);
    public BarkSecretResult Read() {
        if(!OperatingSystem.IsWindows()) return new(BarkSecretState.Unavailable);
        if(!CredRead(Target,1,0,out var pointer)) return new(Marshal.GetLastWin32Error()==NotFound?BarkSecretState.Missing:BarkSecretState.Unavailable);
        try {
            var value=Marshal.PtrToStructure<Credential>(pointer);
            if(value.CredentialBlobSize is 0 or >1024) return new(BarkSecretState.Unavailable);
            var bytes=new byte[value.CredentialBlobSize]; Marshal.Copy(value.CredentialBlob,bytes,0,bytes.Length);
            try { var key=new UTF8Encoding(false,true).GetString(bytes); return QuotaBar.Core.BarkPayload.IsValidDeviceKey(key)?new(BarkSecretState.Available,key):new(BarkSecretState.Unavailable); }
            catch(DecoderFallbackException) { return new(BarkSecretState.Unavailable); }
            finally { Array.Clear(bytes); }
        } finally { CredFree(pointer); }
    }
    public bool Write(string key) {
        if(!OperatingSystem.IsWindows()||!QuotaBar.Core.BarkPayload.IsValidDeviceKey(key)) return false;
        var bytes=Encoding.UTF8.GetBytes(key.Trim()); var blob=Marshal.AllocHGlobal(bytes.Length);
        try { Marshal.Copy(bytes,0,blob,bytes.Length); var value=new Credential { Type=1,TargetName=Target,CredentialBlobSize=(uint)bytes.Length,CredentialBlob=blob,Persist=2,UserName="QuotaBar" }; return CredWrite(ref value,0); }
        finally { for(var i=0;i<bytes.Length;i++) Marshal.WriteByte(blob,i,0); Marshal.FreeHGlobal(blob); Array.Clear(bytes); }
    }
    public bool Clear()=>OperatingSystem.IsWindows()&&(CredDelete(Target,1,0)||Marshal.GetLastWin32Error()==NotFound);
}
