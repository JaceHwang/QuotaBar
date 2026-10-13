#!/usr/bin/env python3
"""Verify candidate files, PE architecture, source fingerprints and optional ZIP."""
import argparse, hashlib, json, pathlib, struct, zipfile

def sha(stream):
    h=hashlib.sha256()
    for block in iter(lambda:stream.read(1024*1024),b""): h.update(block)
    return h.hexdigest()

def main():
    p=argparse.ArgumentParser()
    p.add_argument("package",type=pathlib.Path)
    p.add_argument("--source-root",type=pathlib.Path)
    p.add_argument("--runtime-archive",type=pathlib.Path)
    p.add_argument("--release-tag")
    args=p.parse_args(); package=args.package.resolve()
    manifest=json.loads((package/"package.json").read_text(encoding="utf-8")); provenance=json.loads((package/"PROVENANCE.json").read_text(encoding="utf-8"))
    assert (manifest["schema"],manifest["product"],manifest["platform"],manifest["runtimeVersion"])==(1,"QuotaBar","windows-x64","0.144.1")
    expected=manifest["files"]
    actual={str(f.relative_to(package)).replace("\\","/") for f in package.rglob("*") if f.is_file() and f.name!="package.json"}
    assert actual==set(expected),"Manifest must cover exact payload"
    for name,value in expected.items():
        relative=pathlib.PurePosixPath(name)
        assert not relative.is_absolute() and ".." not in relative.parts and "\\" not in name
        path=package.joinpath(*relative.parts)
        assert not path.is_symlink()
        with path.open("rb") as stream: assert sha(stream)==value,name
    for name in ["QuotaBar.exe","setup/QuotaBar.Setup.exe","runtime/codex.exe"]:
        with (package/name).open("rb") as stream:
            assert stream.read(2)==b"MZ",name
            stream.seek(0x3c); offset=struct.unpack("<I",stream.read(4))[0]
            stream.seek(offset); assert stream.read(4)==b"PE\0\0" and struct.unpack("<H",stream.read(2))[0]==0x8664,name
    assert provenance["runtimeArchiveSHA256"]=="976844ab2d3d77187b70a10c93f0952d6a58b2f67219734fc37785e4334b4c4a"
    assert not provenance["deviceValidated"]  # Exact versioned binaries are checked on CI; device acceptance is separately recorded.
    if args.release_tag:
        assert provenance["kind"]=="release" and provenance["signature"]=="unsigned-release"
        assert provenance["releaseTag"]==args.release_tag and manifest["version"]==args.release_tag[1:]
    else: assert provenance["signature"]=="unsigned-development-candidate"
    if args.source_root:
        for name,value in provenance["sources"].items():
            with args.source_root.joinpath(*pathlib.PurePosixPath(name).parts).open("rb") as stream: assert sha(stream)==value,"Source changed: "+name
    if args.runtime_archive:
        with args.runtime_archive.open("rb") as stream: assert sha(stream)==provenance["runtimeArchiveSHA256"]
        with zipfile.ZipFile(args.runtime_archive) as z:
            with z.open("codex-x86_64-pc-windows-msvc.exe") as stream: assert sha(stream)==expected["runtime/codex.exe"]
    bundles=list(package.parent.glob("QuotaBar-*-windows-x64.zip" if args.release_tag else "QuotaBar-*-windows-x64-candidate.zip"))
    assert len(bundles)==1,"One matching archive required"
    with bundles[0].open("rb") as stream: assert sha(stream)==(package.parent/"SHA256SUMS.txt").read_text().split()[0]
    with zipfile.ZipFile(bundles[0]) as z:
        assert set(z.namelist())=={"QuotaBar/"+name for name in expected}|{"QuotaBar/package.json"}
        for name,value in expected.items():
            with z.open("QuotaBar/"+name) as stream: assert sha(stream)==value,"ZIP mismatch: "+name
    print("PASS Windows candidate: complete files, PE x64, runtime digest, provenance and ZIP checksums")

if __name__=="__main__": main()
