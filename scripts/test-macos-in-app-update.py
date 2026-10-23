#!/usr/bin/env python3
"""Exercise the production native helper using isolated homes and signed fixture apps."""
import hashlib,json,os,pathlib,plistlib,shutil,subprocess,sys,tempfile,time,uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
HELPER=pathlib.Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/'native/.build/debug/QuotaBarUpdater'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def wait(path,process,timeout=25):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if path.exists(): return
        if process.poll() is not None: raise AssertionError('parent exited before expected receipt')
        time.sleep(.05)
    raise AssertionError('receipt timeout')
def run(mode):
    with tempfile.TemporaryDirectory(prefix='quotabar-update-e2e-') as temp:
        root=pathlib.Path(temp).resolve(); home=root/'home'; home.mkdir()
        operation=str(uuid.uuid4()); nonce='a'*64
        directory=home/'Library/Caches/com.jace.codex-quota/Updates'/str(uuid.uuid4()); directory.mkdir(parents=True)
        target=home/'Applications/QuotaBar.app'; target.parent.mkdir()
        # The parent and healthy child are real Mach-O executables at the exact managed app path.
        code=r'''
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/stat.h>
int main(int argc,char **argv) {
 if(argc>1 && !strcmp(argv[1],"--parent")) {
  usleep(500000); pid_t p=fork(); if(p==0) { execl(argv[3],argv[3],argv[2],NULL); _exit(90); }
  char path[4096]; snprintf(path,sizeof(path),"%s/ready.json",argv[2]);
  for(int i=0;i<220;i++) { if(access(path,F_OK)==0) { if(getenv("FIXTURE_STAY")) { while(1) sleep(1); }
   if(!getenv("FIXTURE_CANCEL")) { char commit[4096]; snprintf(commit,sizeof(commit),"%s/handoff.json",argv[2]); FILE *f=fopen(commit,"w"); fprintf(f,"{\"schema\":1,\"operationID\":\"%s\",\"nonce\":\"%s\",\"kind\":\"handoff\"}",getenv("FIXTURE_OPERATION"),getenv("FIXTURE_NONCE")); fclose(f); }
   return 0; } usleep(50000); } kill(p,SIGKILL); return 91;
 }
 if(argc>1 && !strcmp(argv[1],"--update-health")) {
  if(getenv("FIXTURE_EXIT")) return 92;
  char path[4096]; snprintf(path,sizeof(path),"%s/health.json",argv[2]); FILE *f=fopen(path,"w");
  fprintf(f,"{\"schema\":1,\"operationID\":\"%s\",\"nonce\":\"%s\",\"kind\":\"health\"}",getenv("FIXTURE_OPERATION"),argv[3]); fclose(f);
  if(getenv("FIXTURE_RECEIPT_FAILURE")) { snprintf(path,sizeof(path),"%s/succeeded.json",argv[2]); mkdir(path,0700); }
 }
 while(1) sleep(1);
}
'''
        source=root/'fixture.c'; source.write_text(code)
        binary=root/'fixture'; subprocess.run(['xcrun','clang',str(source),'-o',str(binary)],check=True)
        def app(path,version):
            contents=path/'Contents'; (contents/'MacOS').mkdir(parents=True); (contents/'Helpers').mkdir(); (contents/'Resources').mkdir()
            shutil.copy2(binary,contents/'MacOS/CodexQuota'); shutil.copy2(binary,contents/'Helpers/codex'); shutil.copy2(HELPER,contents/'Helpers/QuotaBarUpdater')
            (contents/'Resources/SOURCE-SNAPSHOT.json').write_text('{}')
            with (contents/'Info.plist').open('wb') as f: plistlib.dump(dict(CFBundleIdentifier='com.jace.codex-quota',CFBundleExecutable='CodexQuota',CFBundleShortVersionString=version,CFBundleVersion='1',CFBundlePackageType='APPL',LSMinimumSystemVersion='14.0',CUSStandalone=True),f)
            for item in [contents/'Helpers/codex',contents/'Helpers/QuotaBarUpdater',path]: subprocess.run(['codesign','--force','--sign','-',str(item)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        app(target,'1.3.0'); candidate=directory/'QuotaBar.app'; app(candidate,'2.0.0')
        proof=dict(kind='release',workingTreeDirty=False,version='2.0.0',releaseTag='v2.0.0',sourceCommit='b'*40,runtimeVersion='codex-cli 0.144.1',updateProtocol=1,
                   applicationSignedSha256=sha(candidate/'Contents/MacOS/CodexQuota'),runtimeSignedSha256=sha(candidate/'Contents/Helpers/codex'),updaterSignedSha256=sha(candidate/'Contents/Helpers/QuotaBarUpdater'),sourceSnapshotSha256=sha(candidate/'Contents/Resources/SOURCE-SNAPSHOT.json'))
        proof_path=directory/'proof.json'; proof_path.write_text(json.dumps(proof)); archive=directory/'archive.dmg'; archive.write_bytes(b'fixture envelope')
        def asset(path): return dict(name=path.name,url='https://github.com/JaceHwang/QuotaBar/releases/download/v2.0.0/'+path.name,size=path.stat().st_size,sha256=sha(path))
        release=dict(version='2.0.0',platform='macos-arm64',sourceCommit='b'*40,package=asset(archive),provenance=asset(proof_path))
        helper=directory/'QuotaBarUpdater'; shutil.copy2(HELPER,helper)
        env=dict(os.environ,CFFIXED_USER_HOME=str(home),HOME=str(home),FIXTURE_OPERATION=operation)
        if mode=='rollback': env['FIXTURE_EXIT']='1'
        if mode=='receipt-failure': env['FIXTURE_RECEIPT_FAILURE']='1'
        if mode=='timeout': env['FIXTURE_STAY']='1'
        if mode=='cancel': env['FIXTURE_CANCEL']='1'
        env['FIXTURE_NONCE']=nonce
        log=(root/'helper.log').open('w+')
        parent=subprocess.Popen([str(target/'Contents/MacOS/CodexQuota'),'--parent',str(directory),str(helper)],env=env,stdout=log,stderr=log)
        job=dict(schema=1,operationID=operation,target=str(target),parentPID=parent.pid,nonce=nonce,expiresAt=time.time()-978307200+( -1 if mode=='expired' else 600),release=release)
        (directory/'job.json').write_text(json.dumps(job))
        if mode=='corrupt': (candidate/'Contents/MacOS/CodexQuota').write_bytes(b'changed')
        try:
            if mode=='interrupted':
                parent.kill(); parent.wait()
                store=target.parent/'.QuotaBar-update'; store.mkdir(); backup=store/'backup-interrupted'; target.rename(backup); shutil.copytree(candidate,target)
                (store/'journal.json').write_text(json.dumps(dict(backup=backup.name,stage='stage-interrupted',operationDirectory=str(directory))))
                (directory/'ready.json').write_text(json.dumps(dict(schema=1,operationID=operation,nonce=nonce,kind='ready')))
                live_app=subprocess.Popen([str(target/'Contents/MacOS/CodexQuota')],env=env)
                live_runtime=subprocess.Popen([str(target/'Contents/Helpers/codex')],env=env)
                time.sleep(.2)
                result=subprocess.run([str(helper),'--recover',str(directory),'0'],env=env,capture_output=True,timeout=10)
                assert result.returncode==0,result.stderr
                assert live_app.poll() is not None and live_runtime.poll() is not None, "recovery left the interrupted new app/runtime alive"
                assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='1.3.0'
                assert (directory/'rolledBack.json').exists() and not (store/'journal.json').exists()
            elif mode=='receipt-failure':
                assert parent.wait(timeout=15)==0
                time.sleep(4)
                assert not (directory/'rolledBack.json').exists(), 'committed update misreported as rollback after receipt write failed'
                assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='2.0.0'
                lines=subprocess.check_output(['ps','-axww','-o','command='],text=True).splitlines()
                assert sum(os.path.realpath(line.split(' ',1)[0])==str(target/'Contents/MacOS/CodexQuota') for line in lines)==1, 'receipt failure restarted an already running updated app'
            elif mode=='cancel':
                assert parent.wait(timeout=15)==0
                end=time.monotonic()+8
                while not (directory/'failed.json').exists() and time.monotonic()<end: time.sleep(.05)
                assert (directory/'failed.json').exists(), 'uncommitted parent exit installed an update'
                assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='1.3.0'
            elif mode=='timeout':
                wait(directory/'ready.json',parent)
                end=time.monotonic()+23
                while not (directory/'failed.json').exists() and time.monotonic()<end: time.sleep(.05)
                assert (directory/'failed.json').exists() and parent.poll() is None
                assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='1.3.0'
            elif mode in ('corrupt','expired'):
                time.sleep(2); assert not (directory/'ready.json').exists(); assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='1.3.0'
            else:
                result=parent.wait(timeout=15); log.flush(); log.seek(0); assert result==0, log.read()
                receipt=directory/('rolledBack.json' if mode=='rollback' else 'succeeded.json')
                end=time.monotonic()+25
                while not receipt.exists() and time.monotonic()<end: time.sleep(.05)
                assert receipt.exists(), 'no final receipt'
                value=json.loads(receipt.read_text()); assert value['operationID']==operation and value['nonce']==nonce
                version=plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']; assert version==('1.3.0' if mode=='rollback' else '2.0.0')
                replay=subprocess.run([str(helper),str(directory)],env=env,capture_output=True,timeout=5); assert replay.returncode!=0
            print('PASS native helper '+mode,flush=True)
        finally:
            # Kill only fixture processes with an executable/argument under this isolated temp root.
            listing=subprocess.check_output(['ps','-axww','-o','pid=,command='],text=True)
            for line in listing.splitlines():
                pid,_,command=line.strip().partition(' ')
                if os.path.realpath(command.split(' ',1)[0]).startswith(str(root)+'/') and int(pid)!=os.getpid():
                    try: os.kill(int(pid),9)
                    except ProcessLookupError: pass
            try: parent.wait(timeout=5)
            except subprocess.TimeoutExpired: parent.kill(); parent.wait()
for mode in ['receipt-failure','cancel','happy','rollback','corrupt','expired','timeout','interrupted']: run(mode)
