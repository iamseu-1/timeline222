from pathlib import Path
import json, shutil
root=Path(__file__).resolve().parents[1]
source=root/'data/100k'
target=root/'app/assets/seed'
target.mkdir(parents=True,exist_ok=True)
(target/'originals').mkdir(exist_ok=True)
for p in [source/'archive.db',*(source/'originals').iterdir()]:
    shutil.copyfile(p,target/p.relative_to(source))
files=sorted(p.relative_to(target).as_posix() for p in target.rglob('*') if p.is_file() and p.name!='manifest.json')
(target/'manifest.json').write_bytes((json.dumps(files,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
print('Android 첫 실행용 10만 자료와 원문 3개 준비')
