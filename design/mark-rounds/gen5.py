import math
exec(open('gen.py').read().split('# 1 ·')[0])
def tri_pts(cx,cy,R,rot=-90):
    return [(cx+R*math.cos(math.radians(rot+120*i)), cy+R*math.sin(math.radians(rot+120*i))) for i in range(3)]
def tribar_bands(cx,cy,R,w):
    """Three bands of an impossible triangle. Each band is the quadrilateral between the outer edge (side of the
    triangle of circumradius R) and the inner edge (side of the triangle of circumradius R - w*2/sqrt(3)... ) and is
    cut so that band i overlaps band i+1 at corner i+1 with a mitre that reads as passing over."""
    Ro=R; Ri=R-w*2  # inner triangle radius so that band width across the flat is w (for an equilateral, inradius diff = w → circumradius diff = 2w)
    O=tri_pts(cx,cy,Ro); I=tri_pts(cx,cy,Ri)
    bands=[]
    for i in range(3):
        a,b=O[i],O[(i+1)%3]; ai,bi=I[i],I[(i+1)%3]
        # extend the band's far end past corner i+1 along the side by the band width so it visibly passes over the next band
        dx,dy=b[0]-a[0],b[1]-a[1]; L=math.hypot(dx,dy); ux,uy=dx/L,dy/L
        ext=w*1.15
        bands.append([a,(b[0]+ux*ext,b[1]+uy*ext),(bi[0]+ux*ext*0.0,bi[1]+uy*ext*0.0),ai])
    return bands,O,I
def tribar(kind):
    b=[]; w=11; cx,cy=50,58; R=46
    bands,O,I=tribar_bands(cx,cy,R,w)
    tones=[LIT,HOT,SHADE]   # top-left side faces the light; right side hot; bottom in shade
    # order: draw all three plainly, then redraw each band's head (the extended end) over the next with a slit
    for i in range(3): b.append(piece(bands[i],tones[i],over=False))
    for i in range(3):
        a,bx,bi,ai=bands[i]; dx,dy=bx[0]-a[0],bx[1]-a[1]; L=math.hypot(dx,dy); ux,uy=dx/L,dy/L
        head=[(bx[0]-ux*w*2.6,bx[1]-uy*w*2.6),bx,bi,(ai[0]+ux*(L-w*2.6)*0+ (bi[0]-ux*w*1.4)*0 + (bi[0]-ux*w*1.6), ai[1]*0+(bi[1]-uy*w*1.6))]
        b.append(piece(head,tones[i],over=True))
    if kind=='eye':
        b.append(piece(tri_pts(cx,cy+3,9),PAPER,over=True))
    if kind=='wound':
        # a second, smaller tribar turned 60°, interlocked through the first
        bands2,_,_=tribar_bands(cx,cy+4,25,7)
        rot=[]
        for q in bands2:
            rot.append([(cx+(x-cx)*math.cos(math.pi)-(y-cy-4)*math.sin(math.pi), cy+4+(x-cx)*math.sin(math.pi)+(y-cy-4)*math.cos(math.pi)) for x,y in q])
        t2=[MID,DEEP,PAPER]
        for i in range(3): b.append(piece(rot[i],t2[i],over=True))
    if kind=='sight':
        # the bottom band is cut open in the middle and a paper sight stands in the gap
        b.append(f'<path d="{P(band((44,cy+R/2-w-4),(56,cy+R/2-w-4),0))}" fill="none"/>')
        gap=[(45,cy+R*0.5-2*w-2),(55,cy+R*0.5-2*w-2),(55,cy+R*0.5+3),(45,cy+R*0.5+3)]
        b.append(f'<path d="{P(gap)}" fill="{INK}"/>')
        b.append(piece([(50,cy+R*0.5-2*w-1),(54,cy+R*0.5-4),(46,cy+R*0.5-4)],PAPER,over=True))
    return svg(''.join(b),'Tribar · '+kind)
marks={'tribar-eye':tribar('eye'),'tribar-wound':tribar('wound'),'tribar-sight':tribar('sight')}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'; open('sheet.html','w').write(sheet); print('ok')
