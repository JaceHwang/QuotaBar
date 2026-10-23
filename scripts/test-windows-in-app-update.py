#!/usr/bin/env python3
"""Native helper E2E. Run only on a clean Windows CI/test account (never replace an existing install)."""
import hashlib,json,os,pathlib,shutil,subprocess,sys,time,uuid,zipfile
if os.name!='nt': raise RuntimeError('Native Windows runner required')
package=pathlib.Path(sys.argv[1]).resolve(); local=pathlib.Path(os.environ['LOCALAPPDATA']); target=local/'Programs/QuotaBar'
if target.exists(): raise RuntimeError('Existing install must not be replaced by tests')
if (local/'QuotaBar/CodexHome').exists(): raise RuntimeError('Use a clean test account without real credentials')
setup=package/'setup/QuotaBar.Setup.exe'
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def wait(path,process,seconds=20):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        if path.exists(): return
        if process.poll() is not None: raise AssertionError('Helper exited before receipt')
        time.sleep(.05)
    raise AssertionError('Missing helper receipt')
for mode in ['happy','rollback','corrupt','expired']:
    directory=local/'QuotaBar/Updates'/uuid.uuid4().hex; directory.mkdir(parents=True)
    parent=None; helper=None
    try:
        subprocess.run([str(setup),'install','--candidate',str(package),'--no-launch'],check=True,timeout=120)
        marker=local/'QuotaBar/update-preserved.txt'; marker.write_text('keep')
        candidate=directory/'expanded/QuotaBar'; shutil.copytree(package,candidate)
        if mode=='rollback': shutil.copy2(package/'setup/QuotaBar.Setup.exe',candidate/'QuotaBar.exe') # exits immediately from active install
        proof=json.loads((candidate/'PROVENANCE.json').read_text()); proof.update(kind='release',workingTreeDirty=False,version='2.0.0',releaseTag='v2.0.0',sourceCommit='b'*40,updateProtocol=1)
        (candidate/'PROVENANCE.json').write_text(json.dumps(proof))
        manifest=json.loads((candidate/'package.json').read_text()); manifest['version']='2.0.0'; manifest['files']={p.relative_to(candidate).as_posix():digest(p) for p in candidate.rglob('*') if p.is_file() and p.name!='package.json'}
        (candidate/'package.json').write_text(json.dumps(manifest)); proof_path=directory/'proof.json'; shutil.copy2(candidate/'PROVENANCE.json',proof_path)
        archive=directory/'archive.zip'
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
            for p in candidate.rglob('*'):
                if p.is_file(): z.write(p,'QuotaBar/'+p.relative_to(candidate).as_posix())
        def asset(p): return dict(name=p.name,url='https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/'+p.name,size=p.stat().st_size,sha256=digest(p))
        release=dict(version='2.0.0',platform='windows-x64',sourceCommit='b'*40,package=asset(archive),provenance=asset(proof_path))
        parent=subprocess.Popen([str(target/'QuotaBar.exe')]); time.sleep(2)
        job=dict(schema=1,operationID=uuid.uuid4().hex,target=str(target),parentPID=parent.pid,nonce='a'*64,expiresAt=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()+(-1 if mode=='expired' else 600))),release=release)
        (directory/'job.json').write_text(json.dumps(job)); shutil.copytree(target/'setup',directory/'current-setup')
        if mode=='corrupt': (candidate/'QuotaBar.exe').write_bytes(b'bad')
        helper=subprocess.Popen([str(directory/'current-setup/QuotaBar.Setup.exe'),'update',str(directory)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if mode in ('corrupt','expired'):
            helper.communicate(timeout=30); assert helper.returncode!=0 and not (directory/'ready.json').exists(); assert parent.poll() is None
        else:
            wait(directory/'ready.json',helper); subprocess.run([str(target/'QuotaBar.exe'),'--quit'],check=True,timeout=10); parent.wait(timeout=15)
            out,err=helper.communicate(timeout=90); expected='rolledBack' if mode=='rollback' else 'succeeded'; assert (directory/(expected+'.json')).exists(),(out,err)
            version=json.loads((target/'package.json').read_text())['version']; assert version==('2.0.0' if mode=='happy' else json.loads((package/'package.json').read_text())['version']),(mode,version)
            replay=subprocess.run([str(directory/'current-setup/QuotaBar.Setup.exe'),'update',str(directory)],capture_output=True,timeout=30); assert replay.returncode!=0
        assert marker.read_text()=='keep'; print('PASS Windows native helper '+mode,flush=True)
    finally:
        if target.exists(): subprocess.run([str(target/'QuotaBar.exe'),'--quit'],timeout=10,check=False)
        if helper and helper.poll() is None: helper.kill(); helper.wait()
        if parent and parent.poll() is None: parent.kill(); parent.wait()
        subprocess.run([str(setup),'uninstall'],check=True,timeout=120)
        shutil.rmtree(directory,ignore_errors=True)
        (local/'QuotaBar/update-preserved.txt').unlink(missing_ok=True)
