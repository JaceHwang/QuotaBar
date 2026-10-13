#!/usr/bin/env python3
"""Build and test the Windows release only on a clean immutable tagged checkout."""
import hashlib, json, os, pathlib, shutil, subprocess, sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def git(*args): return subprocess.check_output(["git",*args],cwd=ROOT,text=True).strip()
def sha(path):
    h=hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""): h.update(block)
    return h.hexdigest()
def main():
    tag=sys.argv[1]; version=(ROOT/"version.txt").read_text().strip(); commit=git("rev-parse","HEAD")
    if tag!="v"+version or git("rev-parse",tag+"^{commit}")!=commit or git("status","--porcelain"): raise RuntimeError("Release requires clean exact-tag/version checkout")
    if os.name!="nt": raise RuntimeError("Windows release must be built and installation-tested on Windows")
    build=ROOT/".dist"/"windows-release-build"/tag; assets=ROOT/".dist"/"release"/"windows-x64"
    if assets.exists() and any(assets.iterdir()): raise RuntimeError("Existing release assets will not be overwritten")
    subprocess.run([sys.executable,str(ROOT/"scripts/build-windows-standalone.py"),"--release-tag",tag,"--output",str(build)],cwd=ROOT,check=True)
    package=build/"QuotaBar"
    for script,options in [("verify-windows-standalone.py",["--source-root",str(ROOT),"--release-tag",tag]),("test-windows-standalone-startup.py",[]),("test-windows-standalone-install.py",[])]:
        subprocess.run([sys.executable,str(ROOT/"scripts"/script),str(package),*options],cwd=ROOT,check=True)
    assets.mkdir(parents=True,exist_ok=True)
    archive=build/f"QuotaBar-{version}-windows-x64.zip"; shutil.copy2(archive,assets/archive.name)
    shutil.copy2(package/"PROVENANCE.json",assets/"QUOTABAR-WINDOWS-PROVENANCE.json")
    shutil.copy2(ROOT/"docs/WINDOWS_STANDALONE.zh-CN.md",assets/"QUOTABAR-WINDOWS-INSTALL.zh-CN.md")
    verification={"schema":1,"tag":tag,"sourceCommit":commit,"archiveSHA256":sha(archive),"nativeWindowsStartupExit":True,"nativeWindowsInstallUpgradeRollbackUninstall":True,"deviceAcceptance":"User reports Windows 11 functional acceptance; exact versioned binaries tested on CI"}
    (assets/"QUOTABAR-WINDOWS-VERIFICATION.json").write_text(json.dumps(verification,indent=2)+"\n",encoding="utf-8")
    (assets/"QUOTABAR-WINDOWS-SHA256SUMS.txt").write_text("".join(sha(path)+"  "+path.name+"\n" for path in sorted(assets.iterdir()) if path.is_file()),encoding="utf-8")
    print("Verified native Windows release assets: "+str(assets))
if __name__=="__main__": main()
