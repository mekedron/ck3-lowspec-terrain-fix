# Sharp Terrain Without Advanced Shaders (CK3)

Restores per-pixel terrain detail textures when the graphics option
**Advanced Shaders** is turned off. Vanilla makes the whole map look like a
blurry watercolour in that mode, regardless of the Texture Quality setting.

## Cause

It is not a texture streaming or Texture Quality bug. With Advanced Shaders off
the engine renders the map with `Effect PdxTerrainLowSpec` from
`game/gfx/FX/pdxterrain.shader`, and that effect does the detail texture work in
the **vertex** shader:

    VS_OUTPUT_PDX_TERRAIN_LOW_SPEC TerrainVertexLowSpec( ... )
    {
        ...
        CalculateDetailsLowSpec( Vertex.WorldSpacePos.xz, Out.DetailDiffuse, Out.DetailMaterial );
        Out.ColorMap = ToLinear( PdxTex2DLod0( ColorTexture, ... ).rgb );
        Out.Normal   = CalculateNormal( Vertex.WorldSpacePos.xz );
    }

`DetailDiffuse`, `DetailMaterial`, `ColorMap` and `Normal` are then just
interpolated across each terrain triangle, so the effective ground resolution is
the density of the terrain mesh, not the resolution of the textures. Texture
Quality only controls which mip level gets loaded - the textures are loaded at
full resolution, they are simply sampled once per vertex and smeared.

The high spec `PixelShader` calls `CalculateDetails()` per pixel instead, which
is why turning Advanced Shaders on looks sharp.

## Fix

`gfx/FX/pdxterrain.shader` is a copy of the vanilla file with one new pixel
shader, `PixelShaderLowSpecSharp`, and the two low spec effects rewired to it:

    Effect PdxTerrainLowSpec       VertexShaderLowSpec      -> VertexShader
                                   PixelShaderLowSpec       -> PixelShaderLowSpecSharp
    Effect PdxTerrainLowSpecSkirt  VertexShaderLowSpecSkirt -> VertexShaderSkirt
                                   PixelShaderLowSpec       -> PixelShaderLowSpecSharp

`PixelShaderLowSpecSharp` is the vanilla low spec pixel shader with the
interpolated inputs replaced by per-pixel work:

* `CalculateDetails()` per pixel, with `ddx`/`ddy` driven mip selection, instead
  of the per-vertex `CalculateDetailsLowSpec()` and its `PdxTex2DLod0` sampling
* colormap and terrain normal sampled per pixel
* detail normal maps applied via `ReorientNormal()` - `CalculateDetails()`
  samples them anyway, so this is free; comment that line out for the flat
  vanilla low spec look

Because the effects now use the plain `VertexShader`, the per-vertex detail
sampling is gone entirely, which claws back part of the added pixel cost.

Everything that actually makes Advanced Shaders expensive is still off:
no shadow map lookups, no cloud shadows, no province effects (snow, drought,
flooding), no cubemap/IBL, no overcast contrast, and the cheap
`CalculateTerrainSunLightingLowSpec()` sun lighting. Expect it to land between
vanilla low spec and Advanced Shaders on, much closer to low spec.

Only the terrain is touched. Water, rivers, trees, meshes and the surround map
keep their vanilla low spec variants.

## Layout

    descriptor.mod              mod metadata (read from inside the mod dir)
    gfx/FX/pdxterrain.shader    overrides game/gfx/FX/pdxterrain.shader
    install.sh                  copies the mod into the Proton prefix

## Installing

Run `./install.sh`. It copies the mod into the CK3 mod directory **inside the
Proton prefix**:

    ~/.local/share/Steam/steamapps/compatdata/1158310/pfx/drive_c/users/steamuser/
      Documents/Paradox Interactive/Crusader Kings III/mod/

That is the path the game and the Paradox launcher actually use under Proton.
`~/.local/share/Paradox Interactive/Crusader Kings III` is the native-Linux
location and is *not* read by the Proton build.

Close the launcher before installing, then start it and enable
"Sharp Terrain Without Advanced Shaders" in the playset.

Keep **Advanced Shaders off** in Graphics settings - with it on the game uses
`PdxTerrain`/`PixelShader` and the mod does nothing.

Compiled shaders are cached under `<prefix documents>/Crusader Kings III/shadercache`,
keyed by a hash of the shader source, so the modded shader gets fresh cache
entries by itself. The first load after installing is slower. If the map somehow
still looks unchanged, delete that directory (~900 MB, the game rebuilds it).

## Game version

Built against 1.19.0.6 (Scribe). Shader overrides fully replace the vanilla
file, so after a game patch re-diff `gfx/FX/pdxterrain.shader` against
`<steam>/Crusader Kings III/game/gfx/FX/pdxterrain.shader`. The vanilla
`VertexShaderLowSpec` / `PixelShaderLowSpec` blocks are deliberately left in the
file, unreferenced, to make that diff readable.

## Multiplayer / achievements

Shader files are not checksummed content, but the launcher still marks any mod
as a mod. Treat it like any other graphics mod.
