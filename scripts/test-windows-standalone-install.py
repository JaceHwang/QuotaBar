#!/usr/bin/env python3
"""Windows CI smoke of concrete per-user setup, shortcuts and uninstall recovery."""
import argparse, os, pathlib, shutil, subprocess

def main():
    p=argparse.ArgumentParser(); p.add_argument("package",type=pathlib.Path); args=p.parse_args()
    if os.name!="nt": raise RuntimeError("Windows installation smoke requires Windows")
    target=pathlib.Path(os.environ["LOCALAPPDATA"])/"Programs"/"QuotaBar"
    if target.exists(): raise RuntimeError("Use a clean CI/test machine; existing application is not replaced")
    shortcut=pathlib.Path(os.environ["APPDATA"])/"Microsoft"/"Windows"/"Start Menu"/"Programs"/"QuotaBar.lnk"
    if shortcut.exists(): raise RuntimeError("Existing shortcut is not overwritten by smoke test")
    setup=args.package.resolve()/"setup"/"QuotaBar.Setup.exe"
    def run(*command): subprocess.run([str(setup),*command],check=True,timeout=120)
    run("install","--candidate",str(args.package.resolve()),"--no-launch")
    assert (target/"QuotaBar.exe").is_file() and shortcut.is_file(),"Concrete installation or shortcut missing"
    marker=pathlib.Path(os.environ["LOCALAPPDATA"])/"QuotaBar"/"device-smoke-marker.txt"
    marker.parent.mkdir(parents=True,exist_ok=True); marker.write_text("installation must preserve user data")
    try:
        run("install","--candidate",str(args.package.resolve()),"--no-launch")
        run("rollback"); assert (target/"QuotaBar.exe").is_file()
        run("uninstall"); assert not target.exists() and not shortcut.exists()
        run("rollback"); assert target.exists() and shortcut.exists()
        assert marker.read_text()=="installation must preserve user data"
        run("uninstall")
        print("PASS concrete Windows install, start-menu shortcut, upgrade, rollback, uninstall and user-data preservation")
    finally:
        marker.unlink(missing_ok=True)
        if target.exists(): run("uninstall")

if __name__=="__main__": main()
