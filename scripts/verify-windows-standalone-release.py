#!/usr/bin/env python3
"""Check published Windows ZIP, provenance and native verification against the release tag."""
import hashlib, json, pathlib, subprocess, sys, tempfile, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def git(*args): return subprocess.check_output(["git",*args],cwd=ROOT,text=True).strip()
def sha(path):
    h=hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda:stream.read(1024*1024),b""): h.update(block)
    return h.hexdigest()
def main():
    tag=sys.argv[1]; assets=pathlib.Path(sys.argv[2]).resolve(); version=tag[1:]; commit=git("rev-parse",tag+"^{commit}")
    assert git("rev-parse","HEAD")==commit and (ROOT/"version.txt").read_text().strip()==version
    archive=f"QuotaBar-{version}-windows-x64.zip"
    expected={archive,"QUOTABAR-WINDOWS-PROVENANCE.json","QUOTABAR-WINDOWS-VERIFICATION.json","QUOTABAR-WINDOWS-INSTALL.zh-CN.md"}
    sums={name:value for value,name in (line.split(None,1) for line in (assets/"QUOTABAR-WINDOWS-SHA256SUMS.txt").read_text().splitlines())}
    assert set(sums)==expected
    for name,value in sums.items(): assert sha(assets/name)==value,name
    provenance=json.loads((assets/"QUOTABAR-WINDOWS-PROVENANCE.json").read_text())
    assert provenance["sourceCommit"]==commit and provenance["releaseTag"]==tag and provenance["kind"]=="release" and not provenance["workingTreeDirty"]
    for name,value in provenance["sources"].items():
        data=subprocess.check_output(["git","show",commit+":"+name],cwd=ROOT); assert hashlib.sha256(data).hexdigest()==value,name
    checks=json.loads((assets/"QUOTABAR-WINDOWS-VERIFICATION.json").read_text())
    assert checks["tag"]==tag and checks["sourceCommit"]==commit and checks["archiveSHA256"]==sums[archive]
    assert checks["nativeWindowsStartupExit"] is True and checks["nativeWindowsInstallUpgradeRollbackUninstall"] is True
    with tempfile.TemporaryDirectory() as temporary:
        output=pathlib.Path(temporary)
        with zipfile.ZipFile(assets/archive) as z:
            for name in z.namelist():
                relative=pathlib.PurePosixPath(name); assert not relative.is_absolute() and ".." not in relative.parts and "\\" not in name
            z.extractall(output)
        (output/"SHA256SUMS.txt").write_text(sums[archive]+"  "+archive+"\n")
        # Reuse the full ZIP/payload verifier without duplicating the outer archive.
        source=assets/archive; destination=output/archive
        import shutil
        shutil.copy2(source,destination)
        assert (output/"QuotaBar/PROVENANCE.json").read_bytes()==(assets/"QUOTABAR-WINDOWS-PROVENANCE.json").read_bytes()
        subprocess.run([sys.executable,str(ROOT/"scripts/verify-windows-standalone.py"),str(output/"QuotaBar"),"--source-root",str(ROOT),"--release-tag",tag],check=True)
    print("PASS Windows release tag, source, native checks and all published assets")
if __name__=="__main__": main()
