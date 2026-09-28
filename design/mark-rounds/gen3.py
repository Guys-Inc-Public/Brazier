import math
exec(open('gen.py').read().split('# 1 ·')[0])
C=(13,13); T1,T2=20,70; TONES=[DEEP,SHADE,MID,HOT,LIT]
def fan(b, bands=5, r0=24, step=12, w=8):
    for i in range(bands):
        r1=r0+i*step; b.append(piece(arc(C,r1,r1+w,T1,T2),TONES[i],over=False))
def over_segments(b, idxs, a, span=7, r0=24, step=12, w=8):
    for i in idxs:
        r1=r0+i*step; b.append(piece(arc(C,r1,r1+w,a-span,a+span,8),TONES[i],over=True))
def pivot(b, tone=HOT): b.append(piece([(13,5),(21,13),(13,21),(5,13)],tone,over=True))
# A · Index: one paper index arm weaving over bands 0, 2, 4 and under 1, 3
def index():
    b=[]; fan(b); b.append(piece(band(polar(C,4,45),polar(C,90,45),8),PAPER,over=True)); over_segments(b,(1,3),45); pivot(b); return svg(''.join(b),'Octant · Index')
# B · Vernier: the index arm plus a shorter clamp arm at 30°, weaving the opposite way, crossing nothing but the fan
def vernier():
    b=[]; fan(b)
    b.append(piece(band(polar(C,4,45),polar(C,90,45),8),PAPER,over=True)); over_segments(b,(1,3),45)
    b.append(piece(band(polar(C,4,62),polar(C,74,62),6),DEEP,over=True)); over_segments(b,(0,2,4),62,span=6)
    pivot(b); return svg(''.join(b),'Octant · Vernier')
# C · Reading: no arm; the fan is cut by three slits at 60° steps so every band is a run of stones, and one stone per band is turned to the light (paper) on the reading line
def reading():
    b=[]; fan(b)
    for a in (33,45,57):
        b.append(f'<path d="{P(band(polar(C,20,a),polar(C,96,a),2.4))}" fill="{INK}"/>')
    for i in range(5):
        r1=24+i*12; b.append(piece(arc(C,r1,r1+8,45+1.2,57-1.2,6) if i%2 else arc(C,r1,r1+8,33+1.2,45-1.2,6),PAPER if i==2 else TONES[i],over=False))
    pivot(b,PAPER); return svg(''.join(b),'Octant · Reading')
marks={'octant-index':index(),'octant-vernier':vernier(),'octant-reading':reading()}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'; open('sheet.html','w').write(sheet); print('ok')
