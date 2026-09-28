import math
exec(open('gen.py').read().split('# 1 ·')[0])
def seg(a,b,w,tone,over=True): return piece(cut(a,b,w),tone,over)
def cut(a,b,w,ang=60):
    (x1,y1),(x2,y2)=a,b; dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy); ux,uy=dx/L,dy/L; nx,ny=-uy,ux
    k=w/2/math.tan(math.radians(ang))
    return [(x1+nx*w/2-ux*k,y1+ny*w/2-uy*k),(x2+nx*w/2-ux*k,y2+ny*w/2-uy*k),(x2-nx*w/2+ux*k,y2-ny*w/2+uy*k),(x1-nx*w/2+ux*k,y1-ny*w/2+uy*k)]
# A · Coil: one band wound upward in 60° turns, narrowing like a flame, every turn passing over the one below.
def coil(handle=False):
    b=[]
    # a hexagonal helix seen from the front: each turn = a front run (left→right, rising) and a back run (right→left, rising), narrower each time
    turns=[(18,84,82,74,DEEP),(78,66,22,56,SHADE),(24,48,74,40,MID),(70,32,30,26,HOT),(32,20,56,12,LIT)]
    w=[13,12,11,10,8]
    prev=None
    for i,(x1,y1,x2,y2,t) in enumerate(turns):
        run=cut((x1,y1),(x2,y2),w[i])
        b.append(piece(run,t,over=True))
    b.append(piece([(58,11),(64,4),(66,12),(60,17)],PAPER,over=True))   # the spark at the tip
    if handle:
        b.insert(0,piece(cut((50,96),(50,80),9),DEEP,over=False))
    return svg(''.join(b),'Coil')
# B · Torch: the coil on a handle, with a ring collar (a short bar across) where the flame meets the handle
def torch():
    b=[]
    b.append(piece(cut((50,98),(50,74),9),DEEP,over=False))
    b.append(piece(cut((36,76),(64,76),7),MID,over=True))
    turns=[(24,72,76,64,SHADE),(72,56,28,48,HOT),(30,40,64,32,LIT),(62,24,40,16,HOT)]
    w=[12,11,10,8]
    for i,(x1,y1,x2,y2,t) in enumerate(turns): b.append(piece(cut((x1,y1),(x2,y2),w[i]),t,over=True))
    b.append(piece([(40,15),(46,8),(48,16),(42,21)],PAPER,over=True))
    return svg(''.join(b),'Torch')
# C · Tongues: three tongues of flame, each two bands bent at 60°, woven: the left over the middle, the middle over the right, the right over the left at the tip
def tongues():
    b=[]
    mid=[cut((50,90),(50,52),13),cut((50,52),(64,28),12),cut((64,28),(54,10),9)]
    left=[cut((30,88),(34,56),12),cut((34,56),(50,34),10),cut((50,34),(46,20),7)]
    right=[cut((70,88),(66,58),12),cut((66,58),(48,40),10)]
    for p in right: b.append(piece(p,SHADE,over=False))
    for p in mid: b.append(piece(p,HOT,over=True))
    for p in left: b.append(piece(p,LIT,over=True))
    b.append(piece(right[1],SHADE,over=True))   # the right tongue comes back over at the crossing
    b.append(piece([(54,9),(59,3),(61,10),(56,15)],PAPER,over=True))
    return svg(''.join(b),'Tongues')
marks={'flame-coil':coil(),'flame-torch':torch(),'flame-tongues':tongues()}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'; open('sheet.html','w').write(sheet); print('ok')
