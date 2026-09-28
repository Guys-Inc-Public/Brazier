import math
exec(open('gen.py').read().split('# 1 ·')[0])
def cut(a,b,w,ang=60):
    # a band whose ends are cut at 60° to its axis, like the symbol's arm ends
    (x1,y1),(x2,y2)=a,b; dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy); ux,uy=dx/L,dy/L; nx,ny=-uy,ux
    k=w/2/math.tan(math.radians(ang))
    return [(x1+nx*w/2-ux*k,y1+ny*w/2-uy*k),(x2+nx*w/2-ux*k,y2+ny*w/2-uy*k),(x2-nx*w/2+ux*k,y2-ny*w/2+uy*k),(x1-nx*w/2+ux*k,y1-ny*w/2+uy*k)]
# A · Crier · Ribbon: one ribbon, four runs at 60°, that crosses itself and comes back under its own start: a loop that cannot be tied.
def ribbon():
    w=11; b=[]
    s1=cut((16,28),(72,28),w); s2=cut((72,28),(46,73),w); s3=cut((46,73),(92,73),w); s4=cut((92,73),(64,28),w)
    b.append(piece(s2,HOT,over=False))
    b.append(piece(s3,MID,over=True))       # s3 over the foot of s2
    b.append(piece(s4,SHADE,over=True))     # s4 over s2 and s3
    b.append(piece(s1,LIT,over=True))       # s1 over the head of s4: the loop closes on itself
    b.append(piece(s2[:1]+[s2[1]]+[(s2[1][0]-6,s2[1][1]+10)]+[(s2[0][0]-6,s2[0][1]+10)],HOT,over=True) if False else '')
    return svg(''.join(b),'Crier · Ribbon')
# B · Panoptes · Tribar: three bands in an equilateral triangle, each passing over the next at its corner, so the triangle cannot be built. The opening is the eye.
def tribar():
    w=12; b=[]
    A,Bp,C=(50,14),(88,80),(12,80)
    ab=cut(A,Bp,w); bc=cut(Bp,C,w); ca=cut(C,A,w)
    b.append(piece(ab,HOT,over=False))
    b.append(piece(bc,SHADE,over=True))     # bc over ab at B
    b.append(piece(ca,LIT,over=True))       # ca over bc at C
    # ab over ca at A: redraw the head of ab over ca
    head=cut(A,((A[0]+Bp[0])/2*0.35+A[0]*0.65,(A[1]+Bp[1])/2*0.35+A[1]*0.65),w)
    b.append(piece(head,HOT,over=True))
    b.append(piece([(50,50),(57,62),(43,62)],PAPER,over=True))
    return svg(''.join(b),'Panoptes · Tribar')
# C · Halyard · Hoist: a mast, a halyard that runs over the sheave and under the cleat, and a pennant hoisted to the top, woven through the line.
def hoist():
    b=[]
    mast=cut((30,10),(30,92),9); b.append(piece(mast,DEEP,over=False))
    line_up=band((23,90),(23,16),4); line_down=band((37,16),(37,60),4)
    b.append(piece(line_up,PAPER,over=True)); b.append(piece(line_down,PAPER,over=True))
    sheave=[(30,8),(38,16),(30,24),(22,16)]; b.append(piece(sheave,MID,over=True))
    # pennant: two bands from the mast head, sheared at 60°, the upper over the line and the lower under it
    p1=[(34,20),(92,20),(78,34),(34,34)]; p2=[(34,36),(78,36),(64,50),(34,50)]
    b.append(piece(p2,SHADE,over=False)); b.append(piece(band((37,34),(37,52),4),PAPER,over=True))
    b.append(piece(p1,LIT,over=True))
    cleat=cut((18,66),(42,66),6); b.append(piece(cleat,HOT,over=True))
    return svg(''.join(b),'Halyard · Hoist')
marks={'crier-ribbon':ribbon(),'panoptes-tribar':tribar(),'halyard-hoist':hoist()}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'; open('sheet.html','w').write(sheet); print('ok')
