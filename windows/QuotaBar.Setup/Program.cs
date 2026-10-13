using Microsoft.Win32;
using System.Diagnostics;
using System.Runtime.InteropServices;
using QuotaBar.Core;

if(!OperatingSystem.IsWindows() || Environment.OSVersion.Version.Build<22000 || RuntimeInformation.OSArchitecture!=Architecture.X64) {
    Console.Error.WriteLine("QuotaBar candidate requires Windows 11 x64."); return 1;
}
var target=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","QuotaBar");
var shortcut=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"QuotaBar.lnk");
const string runKey=@"Software\Microsoft\Windows\CurrentVersion\Run";
const string uninstallKey=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\QuotaBar";
var legacyExe=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CodexUsageSidebar","Current","CodexUsageSidebar.Windows.exe");
var legacyFlag=new LegacyPluginFlag(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".codex","config.toml"));
var legacyStartupNames=new[]{"CodexUsageSidebar","Codex Usage Sidebar"};
var command=args.FirstOrDefault()??"install";
try {
    if(Path.GetFullPath(AppContext.BaseDirectory).StartsWith(target+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)) throw new IOException("Run setup from the extracted download or the registered uninstall entry, not the active application folder.");
    var installer=new TransactionInstaller(target,new(StopOwned,StartupEnabled,Activate,Deactivate,CaptureLegacy,SuspendLegacy,RestoreLegacy));
    switch(command) {
        case "install":
            var index=Array.IndexOf(args,"--candidate");
            var candidate=index>=0 && index+1<args.Length ? args[index+1] : Directory.GetParent(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar))!.FullName;
            installer.Install(candidate); Console.WriteLine("QuotaBar installed. Account and preferences preserved.");
            if(!args.Contains("--no-launch")) Process.Start(new ProcessStartInfo(Path.Combine(target,"QuotaBar.exe")) { UseShellExecute=true }); break;
        case "rollback": installer.Rollback(); Console.WriteLine("Recovered previous installation."); break;
        case "uninstall": installer.Uninstall(); Console.WriteLine("Uninstalled. Backup, account and preferences preserved."); break;
        case "recover": installer.RecoverInterrupted(); Console.WriteLine("Interrupted transaction recovered."); break;
        default: throw new IOException("Commands: install [--candidate folder] [--no-launch], rollback, uninstall, recover");
    }
    return 0;
} catch(Exception e) when(e is IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or InvalidOperationException or COMException) {
    Console.Error.WriteLine("QuotaBar setup failed: "+e.Message); return 1;
}
bool StartupEnabled() { using var key=Registry.CurrentUser.OpenSubKey(runKey); return key?.GetValue("QuotaBar") is string; }
void StopOwned() {
    foreach(var p in Process.GetProcessesByName("QuotaBar")) {
        using(p) {
            try {
                if(!string.Equals(p.MainModule?.FileName,Path.Combine(target,"QuotaBar.exe"),StringComparison.OrdinalIgnoreCase)) continue;
                try { using var signal=EventWaitHandle.OpenExisting("Local\\QuotaBar.Shutdown"); signal.Set(); } catch(WaitHandleCannotBeOpenedException) { }
                if(!p.WaitForExit(6000)) { p.Kill(entireProcessTree:true); if(!p.WaitForExit(6000)) throw new IOException("Installed application did not stop"); }
            } catch(InvalidOperationException) { }
        }
    }
}
void Activate(string directory,bool startup) {
    var exe=Path.Combine(directory,"QuotaBar.exe");
    Directory.CreateDirectory(Path.GetDirectoryName(shortcut)!);
    var type=Type.GetTypeFromProgID("WScript.Shell")??throw new IOException("Windows shortcut service unavailable");
    var shell=Activator.CreateInstance(type)!;
    object? link=null;
    try {
        link=type.InvokeMember("CreateShortcut",System.Reflection.BindingFlags.InvokeMethod,null,shell,[shortcut]);
        var linkType=link!.GetType();
        foreach(var (name,value) in new[]{("TargetPath",exe),("WorkingDirectory",directory),("Description","QuotaBar"),("IconLocation",exe+",0")}) linkType.InvokeMember(name,System.Reflection.BindingFlags.SetProperty,null,link,[value]);
        linkType.InvokeMember("Save",System.Reflection.BindingFlags.InvokeMethod,null,link,null);
    } finally { if(link is not null) Marshal.FinalReleaseComObject(link); Marshal.FinalReleaseComObject(shell); }
    using(var run=Registry.CurrentUser.CreateSubKey(runKey)) { if(startup) run.SetValue("QuotaBar",'"'+exe+'"'); else run.DeleteValue("QuotaBar",false); }
    var cache=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"QuotaBarSetup",Guid.NewGuid().ToString("N"));
    CopyDirectory(Path.Combine(directory,"setup"),cache);
    var uninstall=Path.Combine(cache,"QuotaBar.Setup.exe");
    using var key=Registry.CurrentUser.CreateSubKey(uninstallKey);
    key.SetValue("DisplayName","QuotaBar"); key.SetValue("DisplayVersion",PackageVerifier.Verify(directory).Version);
    key.SetValue("Publisher","JaceHwang"); key.SetValue("DisplayIcon",exe); key.SetValue("InstallLocation",directory);
    key.SetValue("UninstallString",'"'+uninstall+"\" uninstall"); key.SetValue("NoModify",1,RegistryValueKind.DWord); key.SetValue("NoRepair",1,RegistryValueKind.DWord);
}
void Deactivate() {
    using(var run=Registry.CurrentUser.OpenSubKey(runKey,true)) run?.DeleteValue("QuotaBar",false);
    Registry.CurrentUser.DeleteSubKeyTree(uninstallKey,false);
    if(File.Exists(shortcut)) File.Delete(shortcut);
}
static void CopyDirectory(string source,string destination) {
    Directory.CreateDirectory(destination);
    foreach(var file in Directory.GetFiles(source)) File.Copy(file,Path.Combine(destination,Path.GetFileName(file)));
    foreach(var dir in Directory.GetDirectories(source)) CopyDirectory(dir,Path.Combine(destination,Path.GetFileName(dir)));
}
bool LegacyCommand(object? value)=>value is string command && string.Equals(command.Trim().Trim('"'),legacyExe,StringComparison.OrdinalIgnoreCase);
LegacyState CaptureLegacy() {
    using var run=Registry.CurrentUser.OpenSubKey(runKey);
    var keys=legacyStartupNames.Where(name=>LegacyCommand(run?.GetValue(name))).ToArray();
    var running=false;
    foreach(var p in Process.GetProcessesByName("CodexUsageSidebar.Windows")) using(p) {
        try { if(string.Equals(p.MainModule?.FileName,legacyExe,StringComparison.OrdinalIgnoreCase)) running=true; }
        catch(InvalidOperationException) { }
    }
    return new(legacyFlag.Read(),running,keys);
}
void SuspendLegacy() {
    legacyFlag.Set(false);
    using(var run=Registry.CurrentUser.OpenSubKey(runKey,true)) foreach(var name in legacyStartupNames) if(LegacyCommand(run?.GetValue(name))) run!.DeleteValue(name,false);
    foreach(var p in Process.GetProcessesByName("CodexUsageSidebar.Windows")) using(p) {
        try {
            if(!string.Equals(p.MainModule?.FileName,legacyExe,StringComparison.OrdinalIgnoreCase)) continue;
            p.Kill(entireProcessTree:true); if(!p.WaitForExit(6000)) throw new IOException("Legacy managed application did not stop");
        } catch(InvalidOperationException) { }
    }
}
void RestoreLegacy(LegacyState state) {
    if(state.PluginEnabled is bool enabled) {
        legacyFlag.Set(enabled);
        if(legacyFlag.Read()!=enabled) throw new IOException("Legacy registration changed during recovery");
    }
    if(state.StartupKeys.Count>0) using(var run=Registry.CurrentUser.CreateSubKey(runKey)) foreach(var name in state.StartupKeys) {
        if(!legacyStartupNames.Contains(name)) throw new IOException("Unexpected legacy startup key");
        var existing=run.GetValue(name);
        if(existing is not null && !LegacyCommand(existing)) throw new IOException("Legacy startup key changed during recovery");
        run.SetValue(name,'"'+legacyExe+'"');
    }
    if(state.WasRunning && File.Exists(legacyExe)) {
        var running=false;
        foreach(var p in Process.GetProcessesByName("CodexUsageSidebar.Windows")) using(p) {
            try { if(string.Equals(p.MainModule?.FileName,legacyExe,StringComparison.OrdinalIgnoreCase)) running=true; }
            catch(InvalidOperationException) { }
        }
        if(!running) Process.Start(new ProcessStartInfo(legacyExe) { UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(legacyExe)! });
    }
}
