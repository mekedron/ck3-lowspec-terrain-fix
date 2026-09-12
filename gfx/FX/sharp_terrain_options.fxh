# Sharp Terrain Without Advanced Shaders - options.
#
# This file is new (no vanilla counterpart) and is the first include of
# gfx/FX/pdxterrain.shader. It only holds #defines. An add-on mod that ships its own
# gfx/FX/sharp_terrain_options.fxh and sits BELOW Sharp Terrain in the load order
# replaces this file and so switches options on without touching the shader itself.
#
# Nothing is defined here in the base mod: this is the plain sharp terrain.

Code
[[
	// TERRAINOPT_SNOW_MATERIAL
	//   The high spec snow material (ApplySnowMaterialTerrain: height blend, normal
	//   map, roughness, frost layer) instead of the flat procedural low spec snow.
	//   About 4 ms of frame time at 5120x1440 in winter on an RTX 3050 Ti Laptop.
	//   Switched on by the "Real Snow Without Advanced Shaders" add-on.
	//#define TERRAINOPT_SNOW_MATERIAL
]]
