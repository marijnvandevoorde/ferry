import random, math, sys
W,H=1500,1000
palettes=[ # sky top, sky bottom, sun, ridge far, ridge near, water?
 ("#1d2b64","#f8cdda","#fff3c4","#6c5b7b","#2a1f3d",True),
 ("#0f2027","#2c5364","#e0f7ff","#33566b","#0e1e26",False),
 ("#ff7e5f","#feb47b","#fff8e1","#b5546a","#4a1f33",True),
 ("#83a4d4","#b6fbff","#ffffff","#5d8aa8","#2f4f4f",False),
 ("#141e30","#243b55","#f5f3ce","#1f3048","#0b1320",True),
 ("#f6d365","#fda085","#fffbe6","#c96a5a","#5b2a2a",False),
 ("#4568dc","#b06ab3","#ffe6f7","#5a3f7a","#26193a",True),
 ("#a1c4fd","#c2e9fb","#fffef2","#7fa7c9","#3c5a73",True),
 ("#355c7d","#f67280","#fff0d9","#6c3f5e","#2b1b2e",False),
 ("#0b486b","#f56217","#ffe2b8","#6b3b2a","#22140f",True),
 ("#56ab2f","#a8e063","#fffde8","#3d7a33","#1f3d1a",False),
 ("#2c3e50","#fd746c","#ffeedd","#5c3b4a","#1e1420",True),
]
def ridge(y0,amp,seed,color,rough):
    r=random.Random(seed); pts=[]; y=y0
    for x in range(0,W+50,50):
        y=y0+amp*math.sin(x/ (180+r.random()*120) + seed)+r.uniform(-rough,rough)
        pts.append(f"{x},{y:.0f}")
    return f'<polygon fill="{color}" points="0,{H} {" ".join(pts)} {W},{H}"/>'
for i,(a,b,sun,far,near,water) in enumerate(palettes):
    r=random.Random(i*7)
    sx,sy,sr=r.randint(300,1200),r.randint(250,450),r.randint(50,110)
    horizon=650 if water else H
    svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}"><defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient><radialGradient id="g"><stop offset="0" stop-color="{sun}" stop-opacity=".9"/><stop offset="1" stop-color="{sun}" stop-opacity="0"/></radialGradient><linearGradient id="w" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{b}"/><stop offset="1" stop-color="{a}"/></linearGradient></defs>',
         f'<rect width="{W}" height="{H}" fill="url(#s)"/>',f'<circle cx="{sx}" cy="{sy}" r="{sr*3.5}" fill="url(#g)"/>',f'<circle cx="{sx}" cy="{sy}" r="{sr}" fill="{sun}"/>']
    if i in (1,4):
        for _ in range(120): svg.append(f'<circle cx="{r.randint(0,W)}" cy="{r.randint(0,500)}" r="{r.uniform(.6,2):.1f}" fill="#fff" opacity="{r.uniform(.3,.9):.2f}"/>')
    base=horizon
    svg.append(ridge(base-260,60,i+1,far,25).replace("<polygon",'<polygon opacity=".55"'))
    svg.append(ridge(base-170,45,i+2,far,15))
    svg.append(ridge(base-80,35,i+3,near,10))
    if water:
        svg.append(f'<rect y="{horizon}" width="{W}" height="{H-horizon}" fill="url(#w)" opacity=".95"/>')
        for k in range(14):
            y=horizon+12+k*k*1.8; w=r.randint(60,220)
            svg.append(f'<rect x="{sx-w/2+r.randint(-30,30)}" y="{y:.0f}" width="{w}" height="3" fill="{sun}" opacity="{0.7-k*0.045:.2f}"/>')
    svg.append('</svg>')
    open(f"scene{i+1:02d}.svg","w").write("".join(svg))
