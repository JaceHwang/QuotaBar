#!/usr/bin/env python3
"""Build a self-contained Windows candidate on Windows or a cross-build host."""
import argparse, datetime, hashlib, json, os, pathlib, shutil, subprocess, urllib.request, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNTIME_VERSION = "0.144.1"
RUNTIME_URL = "https://github.com/openai/codex/releases/download/rust-v0.144.1/codex-x86_64-pc-windows-msvc.exe.zip"
RUNTIME_SHA256 = "976844ab2d3d77187b70a10c93f0952d6a58b2f67219734fc37785e4334b4c4a"

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""): h.update(block)
    return h.hexdigest()

def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)

def source_snapshot():
    source = {}
    for tree in [ROOT / "windows", ROOT / "contracts"]:
        for path in sorted(tree.rglob("*")):
            if path.is_file() and not ({"bin", "obj"} & set(path.relative_to(tree).parts)):
                source[str(path.relative_to(ROOT)).replace(os.sep, "/")] = digest(path)
    for path in [pathlib.Path(__file__), ROOT / "version.txt"]:
        source[str(path.relative_to(ROOT)).replace(os.sep, "/")] = digest(path)
    return source

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dotnet", default="dotnet")
    parser.add_argument("--runtime-archive", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--release-tag")
    args = parser.parse_args()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
    output = (args.output or ROOT / ".dist" / "standalone-windows" / ("candidate-" + stamp)).resolve()
    output.mkdir(parents=True, exist_ok=False)
    package = output / "QuotaBar"
    version = (ROOT / "version.txt").read_text().strip()
    if args.release_tag:
        if args.release_tag != "v" + version: raise RuntimeError("Release tag/version mismatch")
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        tagged = subprocess.check_output(["git", "rev-parse", args.release_tag + "^{commit}"], cwd=ROOT, text=True).strip()
        if commit != tagged or subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip(): raise RuntimeError("Release requires clean exact-tag checkout")
    source = source_snapshot()
    run(args.dotnet, "run", "--project", "windows/QuotaBar.Core.Tests", "--configuration", "Release")
    options = ["--configuration", "Release", "--runtime", "win-x64", "--self-contained", "true", "-p:PublishTrimmed=false", "-p:PublishSingleFile=false", "-p:DebugType=None", "-p:DebugSymbols=false", "-p:Version=" + version]
    run(args.dotnet, "publish", "windows/QuotaBar.Windows", *options, "--output", str(package))
    run(args.dotnet, "publish", "windows/QuotaBar.Setup", *options, "--output", str(package / "setup"))
    archive = args.runtime_archive
    if archive is None:
        archive = output / "runtime.zip"
        urllib.request.urlretrieve(RUNTIME_URL, archive)
    if digest(archive) != RUNTIME_SHA256: raise RuntimeError("Official runtime archive checksum mismatch")
    runtime = package / "runtime"
    runtime.mkdir()
    with zipfile.ZipFile(archive) as z:
        for name in ["codex-x86_64-pc-windows-msvc.exe", "codex-command-runner.exe", "codex-windows-sandbox-setup.exe"]:
            data = z.read(name)
            if not data.startswith(b"MZ"): raise RuntimeError("Expected Windows PE runtime")
            (runtime / ("codex.exe" if name.startswith("codex-x86") else name)).write_bytes(data)
    if os.name == "nt":
        actual = subprocess.check_output([str(runtime / "codex.exe"), "--version"], text=True).strip()
        if actual != "codex-cli " + RUNTIME_VERSION: raise RuntimeError("Runtime version mismatch")
    licenses = package / "licenses"
    licenses.mkdir()
    for name in ["LICENSE", "NOTICE"]:
        urllib.request.urlretrieve("https://raw.githubusercontent.com/openai/codex/rust-v0.144.1/" + name, licenses / ("codex-" + name))
    shutil.copy2(ROOT / "LICENSE", licenses / "QuotaBar-LICENSE")
    shutil.copytree(ROOT / "docs", package / "docs")
    (package / "INSTALL.zh-CN.md").write_text((ROOT / "docs" / "WINDOWS_STANDALONE.zh-CN.md").read_text(encoding="utf-8").replace("(PROJECT_PROGRESS-standalone-app.md)", "(docs/PROJECT_PROGRESS-standalone-app.md)"), encoding="utf-8")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
    if source_snapshot() != source: raise RuntimeError("Build inputs changed during packaging; rebuild from stable source")
    provenance = {"kind": "release" if args.release_tag else "local-development-candidate", "sourceCommit": commit, "workingTreeDirty": dirty, "sources": source, "runtimeSource": RUNTIME_URL, "runtimeArchiveSHA256": RUNTIME_SHA256, "runtimeVersion": RUNTIME_VERSION, "signature": "unsigned-release" if args.release_tag else "unsigned-development-candidate", "deviceValidated": False}
    if args.release_tag: provenance.update(releaseTag=args.release_tag, version=version)
    (package / "PROVENANCE.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    files = {str(p.relative_to(package)).replace(os.sep, "/"): digest(p) for p in sorted(package.rglob("*")) if p.is_file()}
    (package / "package.json").write_text(json.dumps({"schema": 1, "product": "QuotaBar", "platform": "windows-x64", "version": version, "runtimeVersion": RUNTIME_VERSION, "files": files}, indent=2) + "\n", encoding="utf-8")
    bundle = output / ("QuotaBar-" + version + ("-windows-x64.zip" if args.release_tag else "-windows-x64-candidate.zip"))
    with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(package.rglob("*")):
            if path.is_file(): z.write(path, str(path.relative_to(output)).replace(os.sep, "/"))
    (output / "SHA256SUMS.txt").write_text(digest(bundle) + "  " + bundle.name + "\n", encoding="utf-8")
    print("Windows candidate: " + str(bundle))

if __name__ == "__main__": main()
