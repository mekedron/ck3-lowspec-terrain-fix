#!/usr/bin/env python3
"""Compile check for the mod's shaders without starting the game.

The game's shader cache stores every compiled permutation as fully expanded HLSL
(<hash>.scache).  This script takes a vanilla entry for each effect this mod touches,
applies the mod's changes to it (unified diff mod-vs-vanilla, applied with `patch -l`
because the engine dedents Code blocks), prepends the switch block from fastadv.fxh
and compiles the result with DXC - the compiler the game itself uses for Vulkan.

It catches syntax errors, undeclared identifiers and wrong overloads.  It cannot
catch a wrong texture register or an engine-side include problem; those need a game
start (see tools/check_log.sh).

usage: compile_check.py --dxc <dxc dir> [--cache <ps_5_0 dir>] [--game <game root>] [-k]

"""
import argparse, os, re, shutil, subprocess, sys, tempfile

HOME = os.path.expanduser('~')
DEF_CACHE = HOME + '/.local/share/Steam/steamapps/compatdata/1158310/pfx/drive_c/users/steamuser/Documents/Paradox Interactive/Crusader Kings III/shadercache/dx11/ps_5_0'
DEF_GAME = HOME + '/.local/share/Steam/steamapps/common/Crusader Kings III'
MOD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# mod file -> a symbol that proves the file's code is part of an expanded entry
FILES = {
    'pdxterrain.shader': 'CheckClipNeeded',
    'tree.shader': 'DitherThreshold',
    'pdxwater.shader': 'CalcWaterLowSpec',
    'pdxmesh.shader': 'ApplyBakedLighting',
    'pdxmesh_decal.shader': 'CalcDecal',
    'pdxborder.shader': 'PixelShaderStruggle',   # never in expanded text -> matched below by header
    'river_surface.shader': 'CloudyColor',
    'mapname.shader': 'OUTLINE_WIDTH',
    'clouds.fxh': 'GetCloudShadowMask',
    'province_effects.fxh': 'ApplyProvinceEffectsTerrain',
    'dynamic_masks.fxh': 'ApplySnowMaterialTerrain',
    'disease.fxh': 'BlurDiseaseIntensity',
    'jomini/map_lighting.fxh': 'CalculateTerrainDualScenarioLighting',
    'jomini/jomini_province_overlays.fxh': 'CalcDistanceFieldValue',
    'jomini/jomini_water_default.fxh': 'CalcRefraction',
    'jomini/jomini_colormap.fxh': 'BilinearColorSampleAtOffset',
    'bordercolor.fxh': 'GetBorderColorAndBlendGameLerp',
}
# (shader file, effect, low spec?, base) base: 'vanilla' or path of an older mod file.
# MAIN_MAP: effects the mod rewires to a new MainCode - the vanilla main block found in
# the cache entry is replaced by the mod's block of the mapped name.
TARGETS = [
    ('pdxterrain.shader', 'PdxTerrain', False, 'vanilla'),
    ('pdxterrain.shader', 'PdxTerrainLowSpec', True, 'vanilla'),
    ('tree.shader', 'tree', False, 'vanilla'),
    ('tree.shader', 'tree_lod', False, 'vanilla'),
    ('tree.shader', 'tree', True, 'vanilla'),
    ('pdxwater.shader', 'water', False, 'vanilla'),
    ('pdxwater.shader', 'waterLowSpec', True, 'vanilla'),
    ('pdxwater.shader', 'lake', True, 'vanilla'),
    ('pdxmesh.shader', 'standard_atlas', False, 'vanilla'),
    ('pdxmesh.shader', 'standard_usercolor', False, 'vanilla'),
    ('pdxmesh.shader', 'standard_winter', False, 'vanilla'),
    ('pdxmesh_decal.shader', 'decal_local', False, 'vanilla'),
    ('pdxborder.shader', 'PdxBorder', False, 'vanilla'),
    ('pdxborder.shader', 'PdxBorderWar', False, 'vanilla'),
    ('river_surface.shader', 'river_surface', False, 'vanilla'),
    ('mapname.shader', 'mapname', False, 'vanilla'),
]
MAIN_MAP = {('pdxterrain.shader', 'PdxTerrainLowSpec'): {'PixelShaderLowSpec': 'PixelShaderLowSpecSharp'}}

VARIANTS = [
    ('default', []),
    ('snow_material', ['-DTERRAINOPT_SNOW_MATERIAL']),
] if not os.path.exists(os.path.join(MOD, 'gfx/FX/fastadv.fxh')) else [
    ('default', []),
    ('disable_all', ['-DADVOPT_DISABLE_ALL']),
    ('no_lowspec_snow', ['-DADVOPT_NO_LOWSPEC_SNOW_MATERIAL']),
    ('aggressive', ['-DADVOPT_AGGR_TREE_LOWSPEC_LIGHT', '-DADVOPT_AGGR_TREE_CHEAP_SNOW', '-DADVOPT_AGGR_WATER_SIMPLE',
                    '-DADVOPT_AGGR_BORDER_NO_CLOUDS', '-DADVOPT_AGGR_PCF_4', '-DADVOPT_AGGR_TERRAIN_LOWSPEC_LIGHT',
                    '-DADVOPT_AGGR_TERRAIN_CHEAP_SNOW', '-DADVOPT_AGGR_TERRAIN_POINT_OVERLAY']),
    ('diag_flat', ['-DADVOPT_DIAG_TERRAIN_FLAT', '-DADVOPT_DIAG_WATER_FLAT', '-DADVOPT_DIAG_RIVER_FLAT',
                   '-DADVOPT_DIAG_TREE_FLAT', '-DADVOPT_DIAG_MESH_FLAT', '-DADVOPT_DIAG_BORDER_FLAT']),
    ('diag_terrain', ['-DADVOPT_DIAG_TERRAIN_NO_OVERLAY', '-DADVOPT_DIAG_TERRAIN_NO_DETAILS', '-DADVOPT_DIAG_TERRAIN_NO_SNOW',
                      '-DADVOPT_DIAG_TERRAIN_NO_EFFECTS', '-DADVOPT_DIAG_TERRAIN_NO_LIGHTING', '-DADVOPT_DIAG_TERRAIN_NO_FOG']),
]
MOD_MARKERS = ('ADVOPT_', 'TREEOPT_', 'TERRAINOPT_', 'CalcPrimaryProvinceOverlayPoint', 'PixelShaderLowSpecSharp')

def read(p):
    return open(p, 'rb').read().decode('utf-8', 'replace')

def find_entry(cache, shader, effect, lowspec, want_marker, want_block=None):
    for name in sorted(os.listdir(cache)):
        if not name.endswith('.scache'):
            continue
        p = os.path.join(cache, name)
        head = read(p)[:4000]
        if f'// Shader file: gfx/FX/{shader}\n' not in head or f'// Effect: {effect}\n' not in head:
            continue
        has_low = '#define LOW_SPEC_SHADERS' in head
        if has_low != lowspec:
            continue
        text = read(p)
        has_marker = any(m in text for m in MOD_MARKERS)
        if want_marker is None and has_marker:
            continue
        if want_marker and want_marker not in text:
            continue
        if want_block and not contains_lines(text, want_block):
            continue
        return p
    return None

def contains_lines(text, block):
    nl = [l.strip() for l in text.split('\n')]
    pat = [l.strip() for l in block][:40]
    return any(nl[k:k+len(pat)] == pat for k in range(len(nl) - len(pat) + 1))

def switch_block():
    out = ''
    for name in ('fastadv.fxh', 'sharp_terrain_options.fxh', 'better_water_options.fxh'):
        p = os.path.join(MOD, 'gfx/FX', name)
        if os.path.exists(p):
            t = read(p)
            out += t[t.index('[[') + 2: t.index(']]')] + '\n'
    return out

def code_blocks(text):
    """Return {key: [lines]} for every Code [[ ]] block of a Paradox shader file.
    A block that directly follows `MainCode NAME` is keyed ('main', NAME); the other
    (shared) blocks are keyed ('shared', n) in file order."""
    import re
    blocks, shared = {}, 0
    mains = [(m.start(), m.group(1)) for m in re.finditer(r'MainCode\s+(\w+)\s*\{', text)]
    claimed = set()
    for m in re.finditer(r'Code\s*\[\[(.*?)\]\]', text, re.S):
        body = m.group(1).split('\n')
        while body and not body[0].strip(): body.pop(0)
        while body and not body[-1].strip(): body.pop()
        owner = None
        for pos, name in mains:
            if pos < m.start() and name not in claimed:
                owner = name
        # the MainCode that owns this block is the nearest unclaimed one before it,
        # but only if no other Code block sits between them
        if owner is not None:
            pos = [p for p in mains if p[1] == owner][0][0]
            between = re.search(r'Code\s*\[\[', text[pos:m.start()])
            if between is not None:
                owner = None
        if owner is not None:
            claimed.add(owner); key = ('main', owner)
        else:
            key = ('shared', shared); shared += 1
        blocks[key] = body
    return blocks

def apply_blocks(target, vanilla_path, mod_path, main_map=None):
    """Replace every vanilla Code block found in the expanded file with the mod's
    block of the same key (or of the mapped main name). Returns a list of notes."""
    lines = open(target, 'rb').read().decode('utf-8', 'replace').split('\n')
    import re as _re
    sig = _re.compile(r'^\w[\w<>, ]* main\s*\(')
    def norm(l):
        l = l.strip()
        # the engine replaces the PDX_MAIN line of a MainCode block with the real
        # entry point signature; treat both spellings as the same line
        if l.startswith('PDX_MAIN') or sig.match(l):
            return 'PDX_MAIN'
        return l
    van = code_blocks(read(vanilla_path)); mod = code_blocks(read(mod_path))
    for old_main, new_main in (main_map or {}).items():
        if ('main', new_main) in mod:
            mod[('main', old_main)] = mod[('main', new_main)]
    notes = []
    for key, vb in van.items():
        if key not in mod:
            notes.append(f'{key}: no counterpart in mod file'); continue
        pat = [norm(l) for l in vb]
        if not [x for x in pat if x]:
            continue
        nl = [norm(l) for l in lines]
        hits = [k for k in range(len(nl) - len(pat) + 1) if nl[k:k+len(pat)] == pat]
        if not hits:
            continue  # this block is not part of the expanded entry (other MainCode)
        k = hits[0]
        signature = [l for l in lines[k:k+len(pat)] if norm(l) == 'PDX_MAIN']
        new_block = list(mod[key])
        if signature:
            new_block = [signature[0] if norm(l) == 'PDX_MAIN' else l for l in new_block]
        lines[k:k+len(pat)] = new_block
    open(target, 'wb').write('\n'.join(lines).encode('utf-8'))
    return notes

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dxc', required=True)
    ap.add_argument('--cache', default=DEF_CACHE)
    ap.add_argument('--game', default=DEF_GAME)
    ap.add_argument('-k', '--keep', action='store_true', help='keep the work dir')
    a = ap.parse_args()
    dxc = os.path.join(a.dxc, 'bin', 'dxc')
    env = dict(os.environ, LD_LIBRARY_PATH=os.path.join(a.dxc, 'lib'))
    work = tempfile.mkdtemp(prefix='fastadv_')
    failures = 0
    for shader, effect, lowspec, base in TARGETS:
        if not os.path.exists(os.path.join(MOD, 'gfx/FX', shader)):
            continue
        marker = None if base == 'vanilla' else 'TERRAINOPT_SKIP_HIDDEN_TERRAIN'
        # a non-vanilla base must match the entry it is applied to: require the base
        # file's main block for this effect to be present in the expanded text
        want_block = None
        if base != 'vanilla':
            bb = code_blocks(read(base))
            mains = [v for k, v in bb.items() if k[0] == 'main' and 'LowSpecSharp' in k[1]]
            want_block = mains[0] if mains else None
        entry = find_entry(a.cache, shader, effect, lowspec, marker, want_block)
        tag = f'{effect}{"[lowspec]" if lowspec else ""}'
        if not entry:
            print(f'{tag:34} no cache entry, skipped')
            continue
        text = read(entry)
        dst = os.path.join(work, tag + '.hlsl')
        shutil.copy(entry, dst)
        # baseline: the untouched entry must compile with our flags
        r = subprocess.run([dxc, '-T', 'ps_6_0', '-E', 'main', '-HV', '2018', '-Fo', os.devnull, dst], env=env, capture_output=True, text=True)
        if r.returncode:
            print(f'{tag:34} BASELINE FAILS to compile, flags wrong?\n{r.stderr[:1500]}')
            failures += 1
            continue
        # apply the diffs of every mod file whose code is in this entry
        rejected = []
        for f, symbol in FILES.items():
            if not os.path.exists(os.path.join(MOD, 'gfx/FX', f)):
                continue
            if f != shader and symbol not in text:
                continue
            if f == shader and base != 'vanilla':
                van = base
            else:
                van = os.path.join(a.game, 'game/gfx/FX', f)
            modf = os.path.join(MOD, 'gfx/FX', f)
            for msg in apply_blocks(dst, van, modf, MAIN_MAP.get((shader, effect)) if f == shader else None):
                rejected.append(f'{f}: {msg}')
        src = read(dst)
        open(dst, 'w').write(switch_block() + '\n' + src)
        for vname, defs in VARIANTS:
            r = subprocess.run([dxc, '-T', 'ps_6_0', '-E', 'main', '-HV', '2018', '-Fo', os.devnull] + defs + [dst], env=env, capture_output=True, text=True)
            ok = r.returncode == 0
            if not ok:
                failures += 1
            print(f'{tag:34} {vname:12} {"ok" if ok else "FAIL"}')
            if not ok:
                print('    ' + r.stderr.strip().replace('\n', '\n    ')[:3000])
        for rj in rejected:
            print(f'    note: {rj}')
    if a.keep:
        print('work dir:', work)
    else:
        shutil.rmtree(work)
    sys.exit(1 if failures else 0)

if __name__ == '__main__':
    main()
