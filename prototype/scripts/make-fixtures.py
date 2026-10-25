from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from PIL import Image, ImageDraw, ImageFont
import hashlib, json

root = Path(__file__).resolve().parents[1] / 'fixtures'
root.mkdir(exist_ok=True)
font_path = 'C:/Windows/Fonts/malgun.ttf'
pdfmetrics.registerFont(TTFont('Korean', font_path))
body = '별여울의 나루 기록. 푸른 배가 은빛 나루에 머물렀다. 星河 기록과 두 글자 이름 해솔, 별칭 여울을 함께 보관한다.'
(root / '별여울-본문.txt').write_bytes((body + '\n실제 역사 자료가 아닌 검사 원문이다.\n').encode('utf-8'))
c = canvas.Canvas(str(root / '별여울-원문.pdf'), pagesize=(595,842), invariant=1)
c.setTitle('별여울 원문 - 가상 검사 자료')
for page in range(1,4):
    c.setFillColorRGB(.957,.933,.894); c.rect(0,0,595,842,fill=1,stroke=0)
    c.setFillColorRGB(.18,.16,.125); c.setFont('Korean',26); c.drawString(48,755,'별여울의 나루 기록')
    c.setFont('Korean',12); c.drawString(48,713,f'첫째 권  /  {page}쪽  /  오프라인 열람 검사')
    for i,line in enumerate(['푸른 배가 은빛 나루에 머물렀다.','해솔은 그날의 물길을 기록했다.','星河라는 표기와 별칭 여울을 함께 보관한다.','원문의 이름과 본문은 모두 가상이다.','사건에서 출처를 거쳐 이 쪽으로 찾아온다.']):
        c.drawString(48,640-i*34,line)
    c.setFont('Korean',10);c.drawString(48,54,'기존 자료를 바꾸지 않는 성능 시제품용 원문');c.drawRightString(547,54,str(page));c.showPage()
c.save()
im=Image.new('RGB',(1600,1000),'#f4eee4');d=ImageDraw.Draw(im);font=ImageFont.truetype(font_path,48)
d.rounded_rectangle((80,90,1520,910),radius=36,fill='#fcf9f3',outline='#c8b193',width=3)
d.text((140,140),'별여울의 물길 · 가상 삽화',font=font,fill='#2e2820')
for i,col in enumerate(['#a0bcc5','#9dbea8','#d7c18e']):
    d.rounded_rectangle((180+360*i,360,430+360*i,650),radius=34,fill=col)
d.line([(120,760),(440,700),(780,770),(1200,700),(1480,760)],fill='#a0bcc5',width=24)
im.save(root/'별여울-삽화.png')
manifest=[{'path':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in root.iterdir() if p.is_file() and p.suffix in ('.pdf','.png','.txt')]
(root/'manifest.json').write_bytes((json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))
print(json.dumps(manifest,ensure_ascii=False))
