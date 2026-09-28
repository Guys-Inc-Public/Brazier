import math
exec(open('gen.py').read().split('# 1 ·')[0])   # helpers and tones
# Octant "Eighth": a 45° fan of five arc bands stepping deep→lit, the index arm weaving over and under, vernier ticks as slits on the outer band, a paper pivot.
def octant():
    c=(14,14); b=''; tones=[DEEP,SHADE,MID,HOT,LIT]
    t1,t2=22.5,67.5
    for i,t in enumerate(tones):
        r1=24+i*12; r2=r1+8
        b+=piece(arc(c,r1,r2,t1,t2),t,over=False)
    # vernier: four slits cut through the outer band
    for k in range(1,5):
        a=t1+(t2-t1)*k/5; b+=f'<path d="{P(band(polar(c,71,a),polar(c,82,a),2.2))}" fill="{INK}"/>'
    arm=band(polar(c,4,45),polar(c,92,45),8)
    b+=piece(arm,PAPER,over=True)
    for i in (1,3):   # these two bands pass over the arm
        r1=24+i*12; r2=r1+8; b+=piece(arc(c,r1,r2,39,51,8),tones[i],over=True)
    b+=piece([(14,6),(22,14),(14,22),(6,14)],HOT,over=True)
    return svg(b,'Octant mark study')
# Heliograph "Flash": a 60° rhombus mirror, lit face up and shaded face down, a beam arriving from the light and leaving to the right, the shutter bar across the mirror over both.
def heliograph():
    b=''; cx,cy=50,56; h=26*math.sqrt(3)/2
    top=[(cx,cy-h),(cx+26,cy),(cx,cy),(cx-26,cy)]          # two triangles, split along the short diagonal
    bot=[(cx-26,cy),(cx,cy),(cx+26,cy),(cx,cy+h)]
    inb=band((8,10),(cx-6,cy-h+6),9)                      # incoming beam from upper left
    outb=band((cx+6,cy-h+6),(94,14),9)                    # reflected beam to upper right
    b+=piece(bot,SHADE,over=False)+piece(top,LIT,over=False)
    b+=piece(inb,MID,over=True)                           # beams pass over the mirror's edge
    b+=piece(outb,HOT,over=True)
    shutter=band((cx-30,cy+2),(cx+30,cy+2),7)             # the shutter blade, over everything
    b+=piece(shutter,PAPER,over=True)
    legs=[band((cx,cy+h-2),(cx-16,96),7),band((cx,cy+h-2),(cx+16,96),7)]
    b+=piece(legs[0],DEEP,over=False)+piece(legs[1],DEEP,over=False)
    b+=piece([(cx,cy+h-12),(cx+7,cy+h-2),(cx,cy+h+8),(cx-7,cy+h-2)],DEEP,over=True)
    return svg(b,'Heliograph mark study')
# Foghorn "Horn": a horn built of three flaring bands stepping through the tones, two sound chevrons weaving through the mouth, a paper mouthpiece.
def foghorn():
    b=''
    # horn axis from (18,64) to (66,36), flaring; drawn as three parallel bands widening
    def flare(t, off, w0, w1):
        (x1,y1),(x2,y2)=(20,66),(66,40); dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy); nx,ny=-dy/L,dx/L
        return [(x1+nx*(off-w0/2),y1+ny*(off-w0/2)),(x2+nx*(off*1.9-w1/2),y2+ny*(off*1.9-w1/2)),(x2+nx*(off*1.9+w1/2),y2+ny*(off*1.9+w1/2)),(x1+nx*(off+w0/2),y1+ny*(off+w0/2))]
    b+=piece(flare(0,-9,7,10),SHADE,over=False)
    b+=piece(flare(0,0,7,10),HOT,over=False)
    b+=piece(flare(0,9,7,10),LIT,over=False)
    # bell rim: a band across the mouth at 60° to the axis
    rim=band((74,20),(58,58),8); b+=piece(rim,MID,over=True)
    # sound: two chevrons leaving the mouth, the first under the rim, the second over
    ch1=[(78,30),(88,44),(78,58),(84,58),(94,44),(84,30)]; ch2=[(66,26),(76,44),(66,62),(72,62),(82,44),(72,26)]
    b+=piece(ch2,DEEP,over=True)
    b+=piece(rim,MID,over=True)
    b+=piece(ch1,LIT,over=True)
    mouth=[(12,70),(22,64),(26,71),(16,77)]; b+=piece(mouth,PAPER,over=True)
    return svg(b,'Foghorn mark study')
marks={'octant':octant(),'heliograph':heliograph(),'foghorn':foghorn()}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'; open('sheet.html','w').write(sheet); print('ok')
