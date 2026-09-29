#!/usr/bin/env python3
import io, pathlib, plistlib, struct, subprocess, sys, tarfile

pkg=pathlib.Path(sys.argv[1]).resolve()
payload=subprocess.check_output(['dpkg-deb','--fsys-tarfile',str(pkg)])
expected={'FaceIDLabSB':'SpringBoard','FaceIDLabBio':'biometrickitd'}
with tarfile.open(fileobj=io.BytesIO(payload),mode='r:') as t:
    members=t.getmembers()
    assert all(m.isfile() or m.isdir() for m in members), 'links/special files forbidden'
    files={pathlib.PurePosixPath(m.name).name:m for m in members if m.isfile()}
    assert len(files)==4 and len([m for m in members if m.isfile()])==4
    assert set(files)=={n+e for n in expected for e in ('.plist','.dylib')}
    for name,proc in expected.items():
        assert plistlib.loads(t.extractfile(files[name+'.plist']).read())=={'Filter':{'Executables':[proc]}}
        b=t.extractfile(files[name+'.dylib']).read()
        magic,cpu,subtype,kind,ncmds,size=struct.unpack_from('<6I',b)
        assert (magic,cpu,subtype&0xffffff,kind)==(0xfeedfacf,0x100000c,2,6)
        assert all(x in b for x in (b'20F66',b'iPhone14,4',b'MSHookMessageEx',b'observe-only'))
        commands=[];offset=32;dependencies=[]
        for _ in range(ncmds):
            cmd,n=struct.unpack_from('<2I',b,offset);assert n>=8 and offset+n<=32+size
            commands.append(cmd)
            if cmd in (0xc,0x80000018):
                start=struct.unpack_from('<I',b,offset+8)[0]
                dependencies.append(b[offset+start:offset+n].split(b'\0',1)[0].decode())
            offset+=n
        assert 0x1d in commands, 'missing code signature'
        assert any('.jbroot/' in d and ('substrate' in d.lower()) for d in dependencies),dependencies
        assert not any(d.startswith('/var/jb/') for d in dependencies),dependencies
        print(name,'arm64e subtype='+hex(subtype),'dependencies=',dependencies)
control=subprocess.check_output(['dpkg-deb','--ctrl-tarfile',str(pkg)])
with tarfile.open(fileobj=io.BytesIO(control),mode='r:') as t:
    regular=[m for m in t if m.isfile()]
    assert len(regular)==1 and pathlib.PurePosixPath(regular[0].name).name=='control'
    s=t.extractfile(regular[0]).read().decode()
    for x in ['Package: com.chenxun.faceidorientationlab','Version: 0.1.0~alpha1',
              'Architecture: iphoneos-arm64e','Conflicts: com.chenxun.faceidorientationprobe']:
        assert x in s,x
print('PASS: exact filters, four payload files, signed arm64e dylibs, RootHide substrate paths, no install scripts')
