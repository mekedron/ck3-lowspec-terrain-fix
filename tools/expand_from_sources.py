#!/usr/bin/env python3
"""expand_from_sources.py <shader path rel gfx/FX> <MainCode name> <old scache entry> <out.hlsl> [overlay dirs...]
Builds a pixel shader translation unit from current sources: preamble (structs, cbuffers,
samplers, textures) from the old cache entry, then Code blocks of every include in DFS order
(PixelShader and shared ones), then the MainCode body as main()."""
import sys, re, os
GAME=os.path.expanduser('~/.local/share/Steam/steamapps/common/Crusader Kings III/game/gfx/FX')
shader, mainname, old, out = sys.argv[1:5]
overlays = sys.argv[5:]
def path(rel):
    for o in overlays:
        p=os.path.join(o,rel)
        if os.path.exists(p): return p
    for b in (GAME, GAME.replace('/game/gfx/FX','/clausewitz/gfx/FX'), GAME.replace('/game/gfx/FX','/jomini/gfx/FX')):
        if os.path.exists(os.path.join(b,rel)): return os.path.join(b,rel)
    raise FileNotFoundError(rel)
def read(rel): return open(path(rel),encoding='utf-8-sig',errors='replace').read().replace('\r\n','\n')
def strip_comments(t): return re.sub(r'(?m)#.*$','',t)  # pdx '#' comments outside code (approx)
def includes(t):
    m=re.search(r'Includes\s*=\s*\{(.*?)\}',t,re.S)
    return re.findall(r'"([^"]+)"',m.group(1)) if m else []
def blocks(t):
    """yield (section, kind, name, body) for Code / MainCode blocks; section = VertexShader/PixelShader/top"""
    res=[]
    for m in re.finditer(r'(MainCode\s+(\w+)|Code)\s*(\{[^\[]*?)?\[\[(.*?)\]\]',t,re.S):
        pre=t[:m.start()]
        # find enclosing section by last section keyword with unbalanced brace
        sec='top'
        for s in re.finditer(r'\b(VertexShader|PixelShader|ComputeShader|GeometryShader)\s*=\s*\{',pre):
            depth=pre[s.end():].count('{')-pre[s.end():].count('}')
            if depth>=0: sec=s.group(1)
        res.append((sec,'main' if m.group(2) else 'code',m.group(2),m.group(4),m.group(3) or ''))
    return res
seen=set(); code=[]; decls=[]
def visit(rel):
    if rel in seen: return
    seen.add(rel)
    t=read(rel)
    for inc in includes(t): visit(inc)
    for m in re.finditer(r'ConstantBuffer\s*\(\s*(\w+)\s*\)\s*\{(.*?)\}',t,re.S):
        decls.append(('cb',m.group(1),m.group(2)))
    for m in re.finditer(r'TextureSampler\s+(\w+)\s*\{(.*?)\}',t,re.S):
        decls.append(('tex',m.group(1),m.group(2)))
    for m in re.finditer(r'BufferTexture\s+(\w+)\s*\{(.*?)\}',t,re.S):
        decls.append(('buf',m.group(1),m.group(2)))
    for m in re.finditer(r'(?m)^struct\s+(\w+)\s*\{(.*?)\};',t,re.S):
        decls.append(('st',m.group(1),m.group(2)))
    for m in re.finditer(r'VertexStruct\s+(\w+)\s*\{(.*?)\};',t,re.S):
        decls.append(('vs',m.group(1),m.group(2)))
    for sec,kind,name,body,hdr in blocks(t):
        if kind=='code' and sec in ('PixelShader','top'): code.append(f'// ---- {rel}\n'+body)
visit(shader)
t=read(shader)
mains=[b for b in blocks(t) if b[1]=='main' and b[2]==mainname]
assert mains, 'no main'
sec,kind,name,body,hdr=mains[0]
inp=re.search(r'Input\s*=\s*"(\w+)"',hdr).group(1); outp=re.search(r'Output\s*=\s*"(\w+)"',hdr).group(1)
o=open(old,'rb').read().decode('utf-8','replace')
pre=o[:o.index('// === Shader Code ===')]
extra=[]
for kind,name,dbody in decls:
    dbody=re.sub(r'#[^\n]*','',dbody)
    if kind=='buf':
        if re.search(r'\b'+name+r'\s*;',pre): continue
        ty=re.search(r'type\s*=\s*(\w+)',dbody).group(1)
        extra.append(f'PdxBuffer{ty[0].upper()+ty[1:]} {name};'); continue
    if kind=='tex':
        if re.search(r'\b'+name+r'_Texture\b',pre): continue
        ty=(re.search(r'[Tt]ype\s*=\s*"([^"]+)"',dbody) or [None,'2d'])[1].lower()
        T,P={'2d':('Texture2D','PdxTextureSampler2D'),'cube':('TextureCube','PdxTextureSamplerCube'),'2darray':('Texture2DArray','PdxTextureSampler2DArray')}[ty]
        extra.append(f'{T} {name}_Texture;\nstatic {P} {name} = {{ {name}_Texture, _sampler_0_ }};')
    elif kind=='cb':
        mem=[l.strip().rstrip(';') for l in re.sub(r'//.*','',dbody).split('\n') if l.strip() and not l.strip().startswith('#')]
        missing=[x for x in mem if not re.search(r'\b'+re.split(r'[\s\[]+',x.split()[-1])[0]+r'\b\s*(\[.*\])?;',pre)]
        if missing: extra.append('cbuffer extra_'+name+'\n{\n'+'\n'.join('\t'+x+';' for x in missing)+'\n}')
    elif kind=='vs':
        if re.search(r'struct '+name+r'\b',pre): continue
        extra.append(f'struct {name}\n{{{dbody}}};')
    elif kind=='st':
        b=f'struct {name}\n{{{dbody}}};'
        mm=re.search(r'struct '+name+r'\b\s*\{.*?\};',pre,re.S)
        if mm: pre=pre[:mm.start()]+b+pre[mm.end():]
        else: extra.append(b)
pre=pre+'\n// === extra 1.21 decls ===\n'+'\n'.join(extra)+'\n'

oldmain=o[o.index('// === Main Code ==='):]
sig=re.search(r'^.*\bmain\s*\(.*$',oldmain,re.M).group(0)
sig=re.sub(r'main\(\s*\w+ Input','main( '+inp+' Input',sig)
body=body.replace('PDX_MAIN',sig,1)
open(out,'w').write(pre+'// === Shader Code ===\n'+'\n'.join(code)+'\n// === Main Code ===\n'+body+'\n')
print('includes:',len(seen),'code blocks:',len(code),'sig:',sig.strip())
