# Sharp Terrain Without Advanced Shaders - the low spec epidemic hook.
#
# This file is new (no vanilla counterpart). gfx/FX/pdxterrain.shader includes it
# right after disease.fxh and calls ApplyDiseaseDiffuseLowSpec from
# PixelShaderLowSpecSharp, at the point where the high spec pixel shader calls
# vanilla's ApplyDiseaseDiffuse - a call that does nothing with Advanced Shaders off,
# because the whole body of ApplyDiseaseDiffuse sits behind #ifndef LOW_SPEC_SHADERS.
#
# Here the hook is a no-op: Sharp Terrain itself draws no epidemics, and this costs
# nothing. An add-on mod that ships its own gfx/FX/lowspec_disease.fxh and sits BELOW
# Sharp Terrain in the load order replaces this file with a real implementation -
# that is the "Visible Epidemics Without Advanced Shaders" add-on.
#
# The hook is a file of its own rather than another switch in sharp_terrain_options.fxh
# so that an epidemics add-on and the Real Snow add-on can be used at the same time:
# two add-ons cannot both override the options file, but they can override one file each.
#
# The implementation gets the lit terrain colour, the 0-1 map coordinate and the fog of
# war mask; it may sample the mask itself so that the hook costs no texture read at all
# when there is no epidemic on screen.

PixelShader =
{
	Code
	[[
		void ApplyDiseaseDiffuseLowSpec( inout float3 Color, in float2 MapCoords, PdxTextureSampler2D FogOfWarAlphaMask )
		{
		}
	]]
}
