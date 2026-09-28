import math
exec(open('gen.py').read().split('# 1 ·')[0])
def ring_bands(V,w,ext_k=1.5):
    """Bands along the edges of a convex polygon V (clockwise on screen), mitred at each corner, each band's head
    extended past its far corner so it passes over the next band. Returns [(base, head)]."""
    cx=sum(x for x,_ in V)/len(V); cy=sum(y for _,y in V)/len(V); out=[]
    n=len(V)
    for i in range(n):
        A,B=V[i],V[(i+1)%n]; C=V[(i+2)%n]; Z=V[(i-1)%n]
        ux,uy=B[0]-A[0],B[1]-A[1]; L=math.hypot(ux,uy); ux/=L; uy/=L
        nx,ny=-uy,ux
        if (nx*(cx-A[0])+ny*(cy-A[1]))<0: nx,ny=-nx,-ny
        # mitre offsets from the interior angles at A and B
        def half_angle(P,Q,R):
            a1=math.atan2(P[1]-Q[1],P[0]-Q[0]); a2=math.atan2(R[1]-Q[1],R[0]-Q[0]); d=abs(a1-a2)
            d=min(d,2*math.pi-d); return d/2
        kA=w/math.tan(half_angle(Z,A,B)); kB=w/math.tan(half_angle(A,B,C))
        base=[A,B,(B[0]+nx*w-ux*kB,B[1]+ny*w-uy*kB),(A[0]+nx*w+ux*kA,A[1]+ny*w+uy*kA)]
        e=w*ext_k
        head=[(B[0]-ux*w*2.0,B[1]-uy*w*2.0),B,(B[0]+nx*w-ux*kB+ux*e,B[1]+ny*w-uy*kB+uy*e),(B[0]+nx*w-ux*w*2.0,B[1]+ny*w-uy*w*2.0)]
        out.append((base,head))
    return out
FLAME=[(50,4),(76,30),(80,62),(64,92),(36,92),(20,62),(24,30)]    # a flame: sharp apex, round base
TONES6=[HOT,MID,SHADE,DEEP,DEEP,SHADE,LIT]                          # stepping round from the apex: right side hot→deep, left side back up to lit
def flame(kind):
    b=[]; w=10
    bands=ring_bands(FLAME,w)
    for i,(base,head) in enumerate(bands): b.append(piece(base,TONES6[i],over=False))
    for i,(base,head) in enumerate(bands): b.append(piece(head,TONES6[i],over=True))
    if kind=='spark':
        b.append(piece([(50,32),(58,46),(50,60),(42,46)],PAPER,over=True))
    if kind=='inner':
        # Grafana's inner flame: a second, smaller ring set low and to the right, drawn over the outer bands
        inner=[(58,36),(72,54),(68,80),(50,86),(38,68),(44,48)]
        ib=ring_bands(inner,7)
        t2=[LIT,HOT,MID,DEEP,SHADE,PAPER]
        for i,(base,head) in enumerate(ib): b.append(piece(base,t2[i],over=True))
        for i,(base,head) in enumerate(ib): b.append(piece(head,t2[i],over=True))
    if kind=='wick':
        b.append(piece([(46,54),(54,54),(54,84),(46,84)],PAPER,over=True))
        b.append(piece([(50,34),(57,46),(50,56),(43,46)],LIT,over=True))
    return svg(''.join(b),'Flame · '+kind)
marks={'flame-spark':flame('spark'),'flame-inner':flame('inner'),'flame-wick':flame('wick')}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'; open('sheet.html','w').write(sheet); print('ok')
