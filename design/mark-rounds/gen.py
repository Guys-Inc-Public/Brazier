import math, json
INK='#0e090f'; LIT='#ffb3df'; HOT='#ff67bd'; MID='#d64a9b'; SHADE='#a23273'; DEEP='#65204a'; PAPER='#f6f4f7'; LILAC='#a984fb'
def P(pts): return 'M'+' L'.join(f'{x:.2f} {y:.2f}' for x,y in pts)+' Z'
def band(a,b,w):
    (x1,y1),(x2,y2)=a,b; dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy); nx,ny=-dy/L*w/2, dx/L*w/2
    return [(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)]
def arc(c,r1,r2,t1,t2,n=28):
    cx,cy=c; o=[(cx+r2*math.cos(math.radians(t1+(t2-t1)*i/n)), cy+r2*math.sin(math.radians(t1+(t2-t1)*i/n))) for i in range(n+1)]
    i_=[(cx+r1*math.cos(math.radians(t2-(t2-t1)*i/n)), cy+r1*math.sin(math.radians(t2-(t2-t1)*i/n))) for i in range(n+1)]
    return o+i_
def polar(c,r,t): return (c[0]+r*math.cos(math.radians(t)), c[1]+r*math.sin(math.radians(t)))
def piece(pts,tone,over=True,slit=2.4):
    d=P(pts); s=''
    if over: s+=f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="{slit*2}" stroke-linejoin="miter"/>'
    return s+f'<path d="{d}" fill="{tone}"/>'
def svg(body,label): return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="{label}"><rect width="100" height="100" fill="{INK}"/>{body}</svg>'

# 1 · Sextant "Sixth": a 60° arc (a sextant's arc is one sixth of a circle), two frame bands, an index arm across, a mirror at the pivot, a telescope over the left band.
def sextant():
    c=(50,13); w=11
    left=band(polar(c,6,120),polar(c,64,120),w)      # frame, toward the light
    right=band(polar(c,6,60),polar(c,64,60),w)
    arcL=arc(c,50,63,90,124)                          # arc in two halves split by the arm
    arcR=arc(c,50,63,60,90)
    arm=band(polar(c,-2,97),polar(c,70,97),9)        # index arm, over everything
    scope=band(polar(c,30,120-14),polar(c,30,120+14),8)  # a short bar across the left band
    scope=band((polar(c,32,120)[0]-9,polar(c,32,120)[1]+5),(polar(c,32,120)[0]+9,polar(c,32,120)[1]-5),8)
    mirror=[polar(c,0,0)]; mx,my=c; mirror=[(mx,my-6),(mx+6,my),(mx,my+6),(mx-6,my)]
    b=''
    b+=piece(right,SHADE,over=False)
    b+=piece(arcR,MID,over=True)        # arc over the right frame band
    b+=piece(arcL,HOT,over=False)
    b+=piece(left,LIT,over=True)        # left band over the arc: the weave turns the other way
    b+=piece(scope,DEEP,over=True)
    b+=piece(arm,PAPER,over=True)
    b+=piece(mirror,DEEP,over=True)
    return svg(b,'Sextant mark study')

# 2 · Heliograph "Shutter": a mirror plate sheared at 60°, three slats weaving over and under a spine, the flash leaving at 60°, two legs.
def heliograph():
    b=''
    sh=lambda x,y:(x+ (y-50)*(-0.577)*0.0, y)  # no shear helper; explicit points below
    spine=band((50,8),(50,74),10)
    slats=[(LIT,22,True),(MID,40,False),(SHADE,58,True)]   # y, over-spine?
    legs=[band((50,74),(32,96),8),band((50,74),(68,96),8)]
    b+=piece(legs[0],DEEP,over=False)+piece(legs[1],DEEP,over=False)
    b+=piece(spine,HOT,over=False)
    for tone,y,over in slats:
        # a slat is a parallelogram with 60° ends
        s=[(22,y-5),(78,y-5),(74,y+5),(18,y+5)]
        if over: b+=piece(s,tone,over=True)
        else:
            # under the spine: draw the slat, then redraw the spine segment over it with a slit
            b+=piece(s,tone,over=False)
            seg=band((50,y-9),(50,y+9),10); b+=piece(seg,HOT,over=True)
    flash=[(72,20),(96,6),(92,16),(78,26)]
    b+=piece(flash,LIT,over=True)
    return svg(b,'Heliograph mark study')

# 3 · Octant "Eighth": a wedge of four nested arc bands stepping through the tones, an index arm crossing them over-and-under alternately, a paper pivot.
def octant():
    c=(16,16); b=''
    tones=[DEEP,SHADE,MID,HOT]
    for i,t in enumerate(tones):
        r1=22+i*14; r2=r1+9
        b+=piece(arc(c,r1,r2,8,82),t,over=False)
    arm=band(polar(c,2,45),polar(c,88,45),9)
    # weave: the arm passes over bands 1 and 3, under 2 and 4 → redraw those band segments over the arm
    b+=piece(arm,LIT,over=True)
    for i in (1,3):
        r1=22+i*14; r2=r1+9
        b+=piece(arc(c,r1,r2,38,52,8),tones[i],over=True)
    piv=[(16,8),(24,16),(16,24),(8,16)]
    b+=piece(piv,PAPER,over=True)
    return svg(b,'Octant mark study')

marks={'sextant':sextant(),'heliograph':heliograph(),'octant':octant()}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'
open('sheet.html','w').write(sheet); print('ok')
