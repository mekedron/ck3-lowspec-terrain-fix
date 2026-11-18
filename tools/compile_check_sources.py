#!/usr/bin/env python3
"""Patch-day compile check for the whole low spec family, against the CURRENT game sources.

compile_check.py patches expanded shader cache entries, so it only sees a game patch after
the game has been started once on the new version. This script does not need that: for
each target it rebuilds the pixel shader translation unit from the installed game's .fxh
sources plus the mod overlays (tools/expand_from_sources.py), taking only the preamble -
structs, constant buffers, samplers - from any older cache entry and completing it with
declarations the sources add. Every target is also built from plain vanilla (--vanilla):
a vanilla FAIL means the expander missed something, a mod-only FAIL is a real error.

usage: compile_check_sources.py --dxc <dxc dir> [--vanilla]
Sibling repositories are expected next to this one (~/Projects/ck3-*).
"""
import os,subprocess,re,sys
S=os.path.dirname(os.path.abspath(__file__))
import tempfile; W=tempfile.mkdtemp(prefix='ccsrc_')
C=os.path.expanduser('~/.local/share/Steam/steamapps/compatdata/1158310/pfx/drive_c/users/steamuser/Documents/Paradox Interactive/Crusader Kings III/shadercache/dx11/ps_5_0')
P=os.path.expanduser('~/Projects/')
D=sys.argv[sys.argv.index('--dxc')+1]
idx={}
for n in os.listdir(C):
    if not n.endswith('.scache'): continue
    p=os.path.join(C,n); h=open(p,'rb').read(2500).decode('utf-8','replace')
    m1=re.search(r'// Shader file: (\S+)',h); m2=re.search(r'// Effect: (\S+)',h)
    if not m1 or not m2: continue
    key=(m1.group(1),m2.group(1),'#define LOW_SPEC_SHADERS' in h)
    idx.setdefault(key,[]).append((os.path.getmtime(p),p))
def entry(f,e,low):
    l=sorted(idx.get(('gfx/FX/'+f,e,low),[]),reverse=True)
    return l[0][1] if l else None
FX=lambda r: P+r+'/gfx/FX'
tests=[ # name, shader, effect, lowspec, main, overlays, define-variants
 ('terrain low', 'pdxterrain.shader','PdxTerrainLowSpec',True,'PixelShaderLowSpecSharp',[FX('ck3-lowspec-terrain-fix')],[[],['-DTERRAINOPT_SNOW_MATERIAL'],['-DTERRAINOPT_SNOW_MATERIAL','-DTERRAINOPT_SNOW_MATERIAL_VANILLA']]),
 ('terrain high','pdxterrain.shader','PdxTerrain',False,'PixelShader',[FX('ck3-lowspec-terrain-fix')],[[],['-DTERRAINOPT_SNOW_MATERIAL']]),
 ('terrain flat','pdxterrain.shader','PdxTerrainFlat' ,False,'PixelShaderFlatMap',[FX('ck3-lowspec-terrain-fix')],[[]]),
 ('terrain+snow+epid low','pdxterrain.shader','PdxTerrainLowSpec',True,'PixelShaderLowSpecSharp',[FX('ck3-lowspec-epidemics'),FX('ck3-lowspec-real-snow'),FX('ck3-lowspec-terrain-fix')],[[]]),
 ('aio terrain low','pdxterrain.shader','PdxTerrainLowSpec',True,'PixelShaderLowSpecSharp',[FX('ck3-lowspec-all-in-one')],[[]]),
 ('aio terrain high','pdxterrain.shader','PdxTerrain',False,'PixelShader',[FX('ck3-lowspec-all-in-one')],[[]]),
 ('water ocean low','pdxwater.shader','waterLowSpec',True,'PixelShaderLowSpec',[FX('ck3-lowspec-water')],[[],['-DWATEROPT_CHEAP_WAVES']]),
 ('water lake low','pdxwater.shader','lake',True,'PixelShader',[FX('ck3-lowspec-water')],[[],['-DWATEROPT_CHEAP_LAKES']]),
 ('water high','pdxwater.shader','water',False,'PixelShader',[FX('ck3-lowspec-water')],[[]]),
 ('aio water low','pdxwater.shader','waterLowSpec',True,'PixelShaderLowSpec',[FX('ck3-lowspec-all-in-one')],[[]]),
 ('aio lake low','pdxwater.shader','lake',True,'PixelShader',[FX('ck3-lowspec-all-in-one')],[[]]),
 ('coa low','pdxmesh.shader','standard_usercolor_coa',True,'PS_standard',[FX('ck3-lowspec-unit-coa')],[[]]),
 ('coa high','pdxmesh.shader','standard_usercolor_coa',False,'PS_standard',[FX('ck3-lowspec-unit-coa')],[[]]),
 ('aio coa low','pdxmesh.shader','standard_usercolor_coa',True,'PS_standard',[FX('ck3-lowspec-all-in-one')],[[]]),
]
vanilla_too = '--vanilla' in sys.argv
for name,f,e,low,main,ovs,variants in tests:
    en=entry(f,e,low)
    if not en: print(f'{name:24} no cache entry'); continue
    runs=[('mod',ovs)]+([('vanilla',[])] if vanilla_too else [])
    for tag,ov in runs:
        m = main if tag=='mod' else main.replace('LowSpecSharp','LowSpec')
        out=f'{W}/x_{name.replace(" ","_")}_{tag}.hlsl'
        r=subprocess.run(['python3',S+'/expand_from_sources.py',f,m,en,out]+ov,capture_output=True,text=True)
        if r.returncode: print(f'{name:24} {tag} EXPAND FAIL {r.stderr[-300:]}'); continue
        for v in variants:
            r=subprocess.run([D+'/bin/dxc','-T','ps_6_0','-E','main','-HV','2018','-Fo',os.devnull]+v+[out],env=dict(os.environ,LD_LIBRARY_PATH=D+'/lib'),capture_output=True,text=True)
            errs=sorted(set(l for l in r.stderr.split('\n') if 'error' in l))
            print(f'{name:24} {tag:7} {" ".join(v):55} {"OK" if r.returncode==0 else "FAIL"}')
            for l in errs[:4]: print('     ',l[-200:])
