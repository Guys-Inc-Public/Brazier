INK='#0e090f'; LIT='#ffb3df'; HOT='#ff67bd'; MID='#d64a9b'; SHADE='#a23273'; DEEP='#65204a'; PAPER='#f6f4f7'
def path(d,tone,over=False,slit=1.6):
    s=''
    if over: s+=f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="{slit*2}" stroke-linejoin="round"/>'
    return s+f'<path d="{d}" fill="{tone}"/>'
def svg(b,label): return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="{label}"><rect width="100" height="100" fill="{INK}"/>{b}</svg>'
OUTER='M50 94 C24 88 12 62 28 42 C40 28 36 16 64 4 C58 22 80 30 82 52 C84 76 70 94 50 94 Z'
RIGHT='M64 4 C58 22 80 30 82 52 C84 76 70 94 50 94 C68 90 76 74 74 54 C72 36 56 28 64 4 Z'
INNER='M53 86 C38 82 34 66 44 54 C50 46 48 40 58 30 C56 44 70 48 70 62 C70 76 64 86 53 86 Z'
INNER_R='M58 30 C56 44 70 48 70 62 C70 76 64 86 53 86 C64 84 68 72 67 60 C66 48 56 42 58 30 Z'
# 1 · Curl: the outer flame with its right side in shade, a lit inner tongue with its own shaded side, a slit between them
def curl():
    b=path(OUTER,HOT)+path(RIGHT,SHADE)+path(INNER,LIT,over=True)+path(INNER_R,MID)
    return svg(b,'Flame · Curl')
# 2 · Twin: two tongues rising together, the near one lit and passing in front of the far one, which is hot with a shaded back
def twin():
    far='M62 94 C40 90 30 70 42 54 C50 44 46 30 66 12 C62 30 80 36 80 56 C80 78 72 92 62 94 Z'
    far_r='M66 12 C62 30 80 36 80 56 C80 78 72 92 62 94 C74 88 76 72 74 56 C72 40 58 32 66 12 Z'
    near='M40 96 C20 90 16 66 32 52 C44 42 38 26 46 10 C48 28 62 36 60 56 C58 74 52 88 40 96 Z'
    near_r='M46 10 C48 28 62 36 60 56 C58 74 52 88 40 96 C52 86 54 70 52 56 C50 40 42 30 46 10 Z'
    b=path(far,HOT)+path(far_r,SHADE)+path(near,LIT,over=True)+path(near_r,MID)
    return svg(b,'Flame · Twin')
# 3 · Heart: the outer flame, a paper heart of fire (a soft lens) and a deep shadow it throws on the flame's right
def heart():
    lens='M50 30 C58 40 62 50 62 60 C62 72 56 80 50 84 C44 80 38 72 38 60 C38 50 42 40 50 30 Z'
    glow='M50 30 C58 40 62 50 62 60 C62 72 56 80 50 84 C56 76 58 68 58 60 C58 50 55 40 50 30 Z'
    b=path(OUTER,HOT)+path(RIGHT,SHADE)+path(lens,PAPER,over=True)+path(glow,LIT)
    return svg(b,'Flame · Heart')
marks={'soft-curl':curl(),'soft-twin':twin(),'soft-heart':heart()}
for k,v in marks.items(): open(k+'.svg','w').write(v)
sheet='<html><body style="margin:0;background:#0e090f;font-family:sans-serif;color:#969098"><div style="display:flex;gap:40px;padding:24px">'
for k,v in marks.items():
    sheet+=f'<div style="text-align:center"><div style="width:240px">{v}</div><div style="display:flex;gap:16px;justify-content:center;align-items:center;margin-top:12px"><div style="width:64px">{v}</div><div style="width:32px">{v}</div><div style="width:20px">{v}</div></div><div style="font-size:12px;margin-top:8px">{k}</div></div>'
sheet+='</div></body></html>'; open('sheet.html','w').write(sheet); print('ok')
