#!/usr/bin/env python3
"""Windows CI smoke: actual app-server startup and graceful owned-process exit."""
import argparse, ctypes, json, os, pathlib, subprocess, time

def main():
    parser=argparse.ArgumentParser(); parser.add_argument("package",type=pathlib.Path); args=parser.parse_args()
    if os.name!="nt": raise RuntimeError("This smoke test requires Windows")
    data=pathlib.Path(os.environ["LOCALAPPDATA"])/"QuotaBar"
    if (data/"CodexHome"/"auth.json").exists(): raise RuntimeError("Use a clean test account; existing credentials are not modified")
    executable=args.package.resolve()/"QuotaBar.exe"
    app=subprocess.Popen([str(executable)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    children=[]
    try:
        state=None; deadline=time.monotonic()+45
        while time.monotonic()<deadline:
            if app.poll() is not None: raise RuntimeError("Application exited during startup")
            diagnostic=data/"standalone-state.txt"
            try:
                fields=dict(item.split("=",1) for item in diagnostic.read_text().split())
                if fields.get("pid")==str(app.pid) and fields.get("phase") not in (None,"Loading"):
                    state=fields; break
            except (OSError,ValueError): pass
            time.sleep(.2)
        assert state is not None,"No diagnostic from actual process"
        assert state["phase"] in ("NeedsLogin","Ready"),"Runtime startup failed: "+state["phase"]
        raw=subprocess.check_output(["powershell","-NoProfile","-NonInteractive","-Command",f"(Get-CimInstance Win32_Process -Filter 'ParentProcessId = {app.pid}').ProcessId | ConvertTo-Json -Compress"],text=True).strip()
        value=json.loads(raw) if raw else []
        children=value if isinstance(value,list) else [value]
        assert children,"Actual owned runtime missing"
        subprocess.run([str(executable),"--quit"],check=True,timeout=10)
        assert app.wait(timeout=10)==0,"Graceful application exit failed"
        kernel=ctypes.WinDLL("kernel32",use_last_error=True)
        kernel.OpenProcess.restype=ctypes.c_void_p
        kernel.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_bool,ctypes.c_uint32]
        kernel.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint32]
        kernel.CloseHandle.argtypes=[ctypes.c_void_p]
        for pid in children:
            handle=kernel.OpenProcess(0x100000,False,pid)
            if handle:
                try: assert kernel.WaitForSingleObject(handle,1000)==0,"Owned child remained after quit"
                finally: kernel.CloseHandle(handle)
        print("PASS actual Windows standalone startup, official runtime and graceful owned-child exit")
    finally:
        if app.poll() is None:
            subprocess.run([str(executable),"--quit"],timeout=10,check=False)
            try: app.wait(timeout=10)
            except subprocess.TimeoutExpired: app.kill(); app.wait()

if __name__=="__main__": main()
