using Microsoft.Win32;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using Forms=System.Windows.Forms;

namespace QuotaBar.Windows;
internal static class Platform {
    [StructLayout(LayoutKind.Sequential)] public struct NativePoint { public int X,Y; }
    [StructLayout(LayoutKind.Sequential)] public struct NativeRect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out NativePoint p);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out NativeRect rect);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr hwnd,int index);
    [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr hwnd,int index,IntPtr value);
    public static Point Cursor { get { GetCursorPos(out var p); return new(p.X,p.Y); } }
    public static Rect Bounds(Window w) {
        if(!w.IsVisible) return Rect.Empty;
        var hwnd=new WindowInteropHelper(w).Handle;
        return GetWindowRect(hwnd,out var r)?new Rect(r.Left,r.Top,r.Right-r.Left,r.Bottom-r.Top):Rect.Empty;
    }
    public static void Passive(Window w) {
        w.SourceInitialized+=(_,_)=> {
            var h=new WindowInteropHelper(w).Handle;
            SetWindowLongPtr(h,-20,new IntPtr(GetWindowLongPtr(h,-20).ToInt64()|0x08000000|0x80));
        };
    }
    public static WorkArea WorkArea(Point point) {
        var r=Forms.Screen.FromPoint(new System.Drawing.Point((int)point.X,(int)point.Y)).WorkingArea;
        return new(r.X,r.Y,r.Width,r.Height);
    }
    public static void Place(Window w,Point desired,bool clamp=true) {
        var h=new WindowInteropHelper(w).Handle; if(h==IntPtr.Zero) return;
        var scale=GetDpiForWindow(h)/96d; if(scale<=0) scale=1;
        var width=w.Width*scale; var height=w.Height*scale;
        var screen=WorkArea(desired);
        var point=clamp?screen.Clamp(desired.X,desired.Y,width,height):(desired.X,desired.Y);
        SetWindowPos(h,new IntPtr(-1),(int)point.Item1,(int)point.Item2,(int)width,(int)height,0x10|0x40);
    }
    public static bool IsDark(Preferences p) {
        if(SystemParameters.HighContrast) return false;
        if(p.Theme!="system") return p.Theme=="dark";
        using var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int value && value==0;
    }
    public static bool StartupEnabled {
        get { using var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"); return key?.GetValue("QuotaBar") is string; }
    }
    public static void SetStartup(bool enabled) {
        using var key=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if(enabled) key.SetValue("QuotaBar",'"'+Environment.ProcessPath+'"'); else key.DeleteValue("QuotaBar",false);
    }
    public static void OpenUrl(string url) { Process.Start(new ProcessStartInfo(url) { UseShellExecute=true }); }
}

internal sealed class OwnedJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit { public long PerProcess,PerJob; public uint Flags; public UIntPtr Minimum,Maximum; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint Priority,Scheduling; }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes; }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit { public BasicLimit Basic; public IoCounters Io; public UIntPtr ProcessMemory,JobMemory,PeakProcessMemory,PeakJobMemory; }
    [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes,string? name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int info,ref ExtendedLimit value,uint size);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    private IntPtr handle=CreateJobObject(IntPtr.Zero,null);
    public OwnedJob() {
        var info=new ExtendedLimit(); info.Basic.Flags=0x2000;
        if(handle==IntPtr.Zero || !SetInformationJobObject(handle,9,ref info,(uint)Marshal.SizeOf<ExtendedLimit>())) {
            if(handle!=IntPtr.Zero) CloseHandle(handle); handle=IntPtr.Zero; throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
    public void Add(Process p) { if(!AssignProcessToJobObject(handle,p.Handle)) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public void Dispose() { if(handle!=IntPtr.Zero) { CloseHandle(handle); handle=IntPtr.Zero; } }
}

internal sealed class OutsideMouse : IDisposable {
    delegate IntPtr Hook(int code,IntPtr message,IntPtr data);
    [StructLayout(LayoutKind.Sequential)] struct MouseData { public Platform.NativePoint Point; public uint Mouse,Flags,Time; public UIntPtr Extra; }
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id,Hook callback,IntPtr module,uint thread);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string? name);
    readonly Hook callback;
    IntPtr handle;
    public OutsideMouse(Action<Point> pressed) {
        callback=(code,message,data)=> {
            if(code>=0 && (message.ToInt32()==0x201 || message.ToInt32()==0x204)) {
                var p=Marshal.PtrToStructure<MouseData>(data).Point;
                Application.Current.Dispatcher.BeginInvoke(()=>pressed(new(p.X,p.Y)));
            }
            return CallNextHookEx(handle,code,message,data);
        };
        handle=SetWindowsHookEx(14,callback,GetModuleHandle(null),0);
        if(handle==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    public void Dispose() { if(handle!=IntPtr.Zero) { UnhookWindowsHookEx(handle); handle=IntPtr.Zero; } }
}
