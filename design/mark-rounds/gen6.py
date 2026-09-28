import math
exec(open('gen.py').read().split('# 1 ·')[0])
def tri(cx,cy,R,rot=-90): return [(cx+R*math.cos(math.radians(rot+120*i)), cy+R*math.sin(math.radians(rot+120*i))) for i in range(3)]
def frame_bands(cx,cy,R,w,ext):
    O=tri(cx,cy,R); k=w/math.tan(math.radians(60)); out=[]
    for i in range(3):
        A,B=O[i],O[(i+1)%3]; ux,uy=(B[0]-A[0]),(B[1]-A[1]); L=math.hypot(ux,uy); ux/=L; uy/=L
        nx,ny=(cx-A[0]),(cy-A[1]); # inward: toward centroid, take the normal component
        nx,ny=-uy,ux
        if (nx*(cx-A[0])+ny*(cy-A[1]))<0: nx,ny=-nx,-ny
        base=[A,B,(B[0]+nx*w-ux*k,B[1]+ny*w-uy*k),(A[0]+nx*w+ux*k,A[1]+ny*w+uy*k)]
        head=[(B[0]-ux*w*2.2,B[1]-uy*w*2.2),B,(B[0]+nx*w-ux*k+ux*ext,B[1]+ny*w-uy*k+uy*ext),(B[0]+nx*w-ux*w*2.2,B[1]+ny*w-uy*w*2.2)]
        out.append((base,head))
    return out
def tribar(kind):
    b=[]; cx,cy=50,58; R=48; w=12
    tones=[LIT,HOT,SHADE]
    bands=frame_bands(cx,cy,R,w,ext=w*1.5)
    for i,(base,head) in enumerate(bands): b.append(piece(base,tones[i],over=False))
    for i,(base,head) in enumerate(bands): b.append(piece(head,tones[i],over=True))   # each band's head over the next: the joint that cannot be
    if kind=='eye':
        b.append(piece(tri(cx,cy+2,10),PAPER,over=True))
    if kind=='wound':
        inner=frame_bands(cx,cy+3,24,7,ext=7*1.5)
        t2=[MID,DEEP,PAPER]
        # the inner frame is turned 180° so its corners point between the outer corners, and it is drawn over the outer bands
        rot=lambda q:[(2*cx-x, 2*(cy+3)-y) for x,y in q]
        for i,(base,head) in enumerate(inner): b.append(piece(rot(base),t2[i],over=True))
        for i,(base,head) in enumerate(inner): b.append(piece(rot(head),t2[i],over=True))
    if kind=='keep':
        # one corner opened: the top band's head is cut short and a paper wedge stands in the opening, the way the keyhole stands in the Lock ring
        O=tri(cx,cy,R); A=O[0]
        b.append(f'<path d="{P([(A[0]-8,A[1]-2),(A[0]+8,A[1]-2),(A[0]+8,A[1]+16),(A[0]-8,A[1]+16)])}" fill="{INK}"/>')
        b.append(piece([(A[0],A[1]+1),(A[0]+6,A[1]+12),(A[0]-6,A[1]+12)],PAPER,over=True))
    return svg(''.join(b),'Tribar · '+kind)
marks={'tribar-eye':tribar('eye'),'tribar-wound':tribar('wound'),'tribar-keep':tribar('keep')}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'; open('sheet.html','w').write(sheet); print('ok')
