"""Locked, hash-checked VPS publish transaction with a three-APK retention cap."""
import argparse, fcntl, hashlib, json, os, pathlib, re, grp
FIELDS=('versionCode','versionName','sha256','releaseId')
def valid(m):
    code=m.get('versionCode',m.get('installVersionCode'))
    assert type(code) is int and code>0
    assert re.fullmatch(r'[0-9a-f]{64}',m['sha256'])
    assert m['releaseId']==f"v{code}-{m['sha256'][:12]}"
    assert type(m['sizeBytes']) is int and m['sizeBytes']>0
    return code
def plan(items,current):
    assert current in items
    ranked=sorted(items,key=lambda k:valid(items[k]),reverse=True)
    keep=[current]+[k for k in ranked if k!=current][:2]
    return set(keep)
def checked(path,meta):
    assert not path.is_symlink() and path.is_file()
    assert path.stat().st_size==meta['sizeBytes']
    with path.open('rb') as f: assert hashlib.file_digest(f,'sha256').hexdigest()==meta['sha256']
def atomic(path,data):
    temp=path.with_suffix(path.suffix+'.pending')
    with temp.open('w') as f:
        json.dump(data,f,ensure_ascii=False,indent=2); f.flush(); os.fsync(f.fileno())
    os.chown(temp,0,grp.getgrnam('caddy').gr_gid); temp.chmod(0o640)
    os.replace(temp,path)
def main(rid):
    assert re.fullmatch(r'v\d+-[0-9a-f]{12}',rid)
    base=pathlib.Path('/srv/feimiao-updates')
    assert base.resolve()==base and not base.is_symlink()
    public=base/'public'; releases=public/'releases'
    assert releases.resolve()==releases
    with (base/'publish.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        incoming=base/'incoming'/rid
        assert incoming.resolve()==incoming
        candidate=json.loads((incoming/'version.json').read_text()); code=valid(candidate)
        assert candidate['releaseId']==rid
        checked(incoming/'app.apk',candidate)
        current=json.loads((public/'version.json').read_text()); valid(current)
        catalog=json.loads((public/'rollback.json').read_text())
        entries=catalog['versions']; assert isinstance(entries,list)
        for entry in entries: valid(entry)
        assert code>=current['versionCode'],'Cannot downgrade production'
        if code==current['versionCode']:
            assert all(candidate[k]==current[k] for k in FIELDS),'Identity collision'
        else:
            assert code>max([e['installVersionCode'] for e in entries]+[0]),'Version reserved by rollback'
        items={}
        for path in releases.iterdir():
            assert not path.is_symlink()
            assert re.fullmatch(r'v\d+-[0-9a-f]{12}\.(apk|json)',path.name),'Unknown release file; stop'
            if path.suffix=='.json':
                m=json.loads(path.read_text()); valid(m); assert path.stem==m['releaseId']
                checked(path.with_suffix('.apk'),m); items[path.stem]=m
        assert {p.stem for p in releases.glob('*.apk')}==set(items),'Untracked APK; stop'
        if rid in items: assert items[rid]['sha256']==candidate['sha256']
        dest=releases/(rid+'.apk')
        if not dest.exists(): os.replace(incoming/'app.apk',dest)
        os.chown(dest,0,grp.getgrnam('caddy').gr_gid); dest.chmod(0o640)
        candidate['url']='https://updates.xunni.dpdns.org/feimiao-latest.apk?release='+rid
        atomic(releases/(rid+'.json'),candidate)
        items[rid]=candidate; keep=plan(items,rid)
        # Publish files first; metadata pointer last. Cleanup never precedes publication.
        link=public/'current.apk.pending'
        if link.is_symlink(): link.unlink()
        link.symlink_to('releases/'+rid+'.apk'); os.replace(link,public/'current.apk')
        atomic(public/'version.json',candidate)
        catalog['versions']=[e for e in entries if e['releaseId'] in keep]
        atomic(public/'rollback.json',catalog)
        assert json.loads((public/'version.json').read_text())['releaseId']==rid
        for old in set(items)-keep:
            for suffix in ('.apk','.json'):
                target=releases/(old+suffix)
                assert target.parent.resolve()==releases and not target.is_symlink()
                target.unlink()
        for name in ('version.json','app.apk'):
            target=incoming/name
            if target.exists(): target.unlink()
        incoming.rmdir()
        assert len(list(releases.glob('*.apk')))<=3
        print(json.dumps({'published':rid,'retained':sorted(keep),'apkCount':len(keep)}))
if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('release_id'); args=parser.parse_args()
    main(args.release_id)
