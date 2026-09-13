# Sharp Terrain Without Advanced Shaders - modified copy of
# game/gfx/FX/pdxterrain.shader from CK3 1.19.0.6 (Scribe).
#
# Options live in gfx/FX/sharp_terrain_options.fxh (included first). Add-on mods
# override that one file to switch options on - see the README. Currently:
#   TERRAINOPT_SNOW_MATERIAL  the snow material in the low spec pixel shader (the
#                             "Real Snow Without Advanced Shaders" add-on), drawn by
#                             ApplySnowMaterialTerrainCheap, a new function in this file
#   TERRAINOPT_SNOW_MATERIAL_VANILLA  vanilla's ApplySnowMaterialTerrain instead of the
#                             cheap one (about twice the texture reads plus noise math)
#
# Vanilla evaluates the terrain detail textures per *vertex* when "Advanced
# Shaders" is off (CalculateDetailsLowSpec is called from TerrainVertexLowSpec
# and the result is passed down as an interpolant), which smears the ground
# textures no matter how high Texture Quality is set.
#
# This file only changes the two low spec terrain effects so that the detail
# textures are sampled per *pixel* instead, while keeping the rest of the low
# spec path (no shadows, no clouds, no province effects, no cubemap, simplified
# sun lighting). Everything else is vanilla.
#
# Changes vs vanilla, all at the bottom of the file plus one new MainCode block:
#   * new MainCode PixelShaderLowSpecSharp
#   * new function ApplySnowMaterialTerrainCheap in the PixelShader Code block
#   * Effect PdxTerrainLowSpec      -> VertexShader + PixelShaderLowSpecSharp
#   * Effect PdxTerrainLowSpecSkirt -> VertexShaderSkirt + PixelShaderLowSpecSharp
#   * #define TERRAINOPT_SKIP_HIDDEN_TERRAIN in the PixelShader Code block, and
#     the early out it guards inside PixelShaderLowSpecSharp
# The vanilla VertexShaderLowSpec / PixelShaderLowSpec blocks are left in place,
# unreferenced, for diffing against future game patches.

Includes = {
	"sharp_terrain_options.fxh"
	"cw/pdxterrain.fxh"
	"cw/heightmap.fxh"
	"cw/shadow.fxh"
	"cw/utility.fxh"
	"cw/camera.fxh"
	"cw/lighting_util.fxh"
	"cw/lighting.fxh"
	"jomini/jomini_fog.fxh"
	"jomini/map_lighting.fxh"
	"jomini/jomini_fog_of_war.fxh"
	"jomini/jomini_water.fxh"
	"standardfuncsgfx.fxh"
	"bordercolor.fxh"
	"lowspec.fxh"
	"legend.fxh"
	"dynamic_masks.fxh"
	"disease.fxh"
	"shadow_tint.fxh"
	"clouds.fxh"
	"province_effects.fxh"
	"paper_transition.fxh"
	"utility_game.fxh"
}

VertexStruct VS_OUTPUT_PDX_TERRAIN
{
	float4 Position			: PDX_POSITION;
	float3 WorldSpacePos	: TEXCOORD1;
	float4 ShadowProj		: TEXCOORD2;
};

VertexStruct VS_OUTPUT_PDX_TERRAIN_LOW_SPEC
{
	float4 Position			: PDX_POSITION;
	float3 WorldSpacePos	: TEXCOORD1;
	float4 ShadowProj		: TEXCOORD2;
	float3 DetailDiffuse	: TEXCOORD3;
	float4 DetailMaterial	: TEXCOORD4;
	float3 ColorMap			: TEXCOORD5;
	float3 FlatMap			: TEXCOORD6;
	float3 Normal			: TEXCOORD7;
};

# Limited JominiEnvironment data to get nicer transitions between the Flatmap lighting and Terrain lighting
# Only used in terrain shader while lerping between flatmap and terrain.
ConstantBuffer( FlatMapLerpEnvironment )
{
	float	FlatMapLerpCubemapIntensity;
	float3	FlatMapLerpSunDiffuse;
	float	FlatMapLerpSunIntensity;
	float4x4 FlatMapLerpCubemapYRotation;
};

VertexShader =
{
	TextureSampler DetailTextures
	{
		Ref = PdxTerrainTextures0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}
	TextureSampler NormalTextures
	{
		Ref = PdxTerrainTextures1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}
	TextureSampler MaterialTextures
	{
		Ref = PdxTerrainTextures2
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}
	TextureSampler DetailIndexTexture
	{
		Ref = PdxTerrainTextures3
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler DetailMaskTexture
	{
		Ref = PdxTerrainTextures4
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler ColorTexture
	{
		Ref = PdxTerrainColorMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler FlatMapTexture
	{
		Ref = TerrainFlatMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}

	Code
	[[
		VS_OUTPUT_PDX_TERRAIN TerrainVertex( float2 WithinNodePos, float2 NodeOffset, float NodeScale, float2 LodDirection, float LodLerpFactor )
		{
			STerrainVertex Vertex = CalcTerrainVertex( WithinNodePos, NodeOffset, NodeScale, LodDirection, LodLerpFactor );

			#ifdef TERRAIN_FLAT_MAP_LERP
				Vertex.WorldSpacePos.y = lerp( Vertex.WorldSpacePos.y, FlatMapHeight, FlatMapLerp );
			#endif
			#ifdef TERRAIN_FLAT_MAP
				Vertex.WorldSpacePos.y = FlatMapHeight;
			#endif

			VS_OUTPUT_PDX_TERRAIN Out;
			Out.WorldSpacePos = Vertex.WorldSpacePos;

			Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );
			Out.ShadowProj = mul( ShadowMapTextureMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );

			return Out;
		}

		// Copies of the pixels shader CalcHeightBlendFactors and CalcDetailUV functions
		float4 CalcHeightBlendFactors( float4 MaterialHeights, float4 MaterialFactors, float BlendRange )
		{
			float4 Mat = MaterialHeights + MaterialFactors;
			float BlendStart = max( max( Mat.x, Mat.y ), max( Mat.z, Mat.w ) ) - BlendRange;

			float4 MatBlend = max( Mat - vec4( BlendStart ), vec4( 0.0 ) );

			float Epsilon = 0.00001;
			return float4( MatBlend ) / ( dot( MatBlend, vec4( 1.0 ) ) + Epsilon );
		}

		float2 CalcDetailUV( float2 WorldSpacePosXZ )
		{
			return (WorldSpacePosXZ + DetailTileOffset) * DetailTileFactor;
		}

		// A low spec vertex buffer version of CalculateDetails
		void CalculateDetailsLowSpec( float2 WorldSpacePosXZ, out float3 DetailDiffuse, out float4 DetailMaterial )
		{
			float2 DetailCoordinates = WorldSpacePosXZ * WorldSpaceToDetail;
			float2 DetailCoordinatesScaled = DetailCoordinates * DetailTextureSize;
			float2 DetailCoordinatesScaledFloored = floor( DetailCoordinatesScaled );
			float2 DetailCoordinatesFrac = DetailCoordinatesScaled - DetailCoordinatesScaledFloored;
			DetailCoordinates = DetailCoordinatesScaledFloored * DetailTexelSize + DetailTexelSize * 0.5;

			float4 Factors = float4(
				(1.0 - DetailCoordinatesFrac.x) * (1.0 - DetailCoordinatesFrac.y),
				DetailCoordinatesFrac.x * (1.0 - DetailCoordinatesFrac.y),
				(1.0 - DetailCoordinatesFrac.x) * DetailCoordinatesFrac.y,
				DetailCoordinatesFrac.x * DetailCoordinatesFrac.y
			);

			float4 DetailIndex = PdxTex2DLod0( DetailIndexTexture, DetailCoordinates ) * 255.0;
			float4 DetailMask = PdxTex2DLod0( DetailMaskTexture, DetailCoordinates ) * Factors[0];

			float2 Offsets[3];
			Offsets[0] = float2( DetailTexelSize.x, 0.0 );
			Offsets[1] = float2( 0.0, DetailTexelSize.y );
			Offsets[2] = float2( DetailTexelSize.x, DetailTexelSize.y );

			for ( int k = 0; k < 3; ++k )
			{
				float2 DetailCoordinates2 = DetailCoordinates + Offsets[k];

				float4 DetailIndices = PdxTex2DLod0( DetailIndexTexture, DetailCoordinates2 ) * 255.0;
				float4 DetailMasks = PdxTex2DLod0( DetailMaskTexture, DetailCoordinates2 ) * Factors[k+1];

				for ( int i = 0; i < 4; ++i )
				{
					for ( int j = 0; j < 4; ++j )
					{
						if ( DetailIndex[j] == DetailIndices[i] )
						{
							DetailMask[j] += DetailMasks[i];
						}
					}
				}
			}

			// We don't use different detail UVs per material like in the normal pdxterrain shader
			float2 DetailUV = CalcDetailUV( WorldSpacePosXZ );

			float4 DiffuseTexture0 = PdxTex2DLod0( DetailTextures, float3( DetailUV, DetailIndex[0] ) ) * smoothstep( 0.0, 0.1, DetailMask[0] );
			float4 DiffuseTexture1 = PdxTex2DLod0( DetailTextures, float3( DetailUV, DetailIndex[1] ) ) * smoothstep( 0.0, 0.1, DetailMask[1] );
			float4 DiffuseTexture2 = PdxTex2DLod0( DetailTextures, float3( DetailUV, DetailIndex[2] ) ) * smoothstep( 0.0, 0.1, DetailMask[2] );
			float4 DiffuseTexture3 = PdxTex2DLod0( DetailTextures, float3( DetailUV, DetailIndex[3] ) ) * smoothstep( 0.0, 0.1, DetailMask[3] );

			float4 BlendFactors = CalcHeightBlendFactors( float4( DiffuseTexture0.a, DiffuseTexture1.a, DiffuseTexture2.a, DiffuseTexture3.a ), DetailMask, DetailBlendRange );

			DetailDiffuse = DiffuseTexture0.rgb * BlendFactors[0] +
							DiffuseTexture1.rgb * BlendFactors[1] +
							DiffuseTexture2.rgb * BlendFactors[2] +
							DiffuseTexture3.rgb * BlendFactors[3];

			DetailMaterial = vec4( 0.0 );

			for ( int i = 0; i < 4; ++i )
			{
				float BlendFactor = BlendFactors[i];
				if ( BlendFactor > 0.0 )
				{
					float3 ArrayUV = float3( DetailUV, DetailIndex[i] );
					float4 NormalTexture = PdxTex2DLod0( NormalTextures, ArrayUV );
					float4 MaterialTexture = PdxTex2DLod0( MaterialTextures, ArrayUV );

					DetailMaterial += MaterialTexture * BlendFactor;
				}
			}
		}

		VS_OUTPUT_PDX_TERRAIN_LOW_SPEC TerrainVertexLowSpec( float2 WithinNodePos, float2 NodeOffset, float NodeScale, float2 LodDirection, float LodLerpFactor )
		{
			STerrainVertex Vertex = CalcTerrainVertex( WithinNodePos, NodeOffset, NodeScale, LodDirection, LodLerpFactor );

			#ifdef TERRAIN_FLAT_MAP_LERP
				Vertex.WorldSpacePos.y = lerp( Vertex.WorldSpacePos.y, FlatMapHeight, FlatMapLerp );
			#endif
			#ifdef TERRAIN_FLAT_MAP
				Vertex.WorldSpacePos.y = FlatMapHeight;
			#endif

			VS_OUTPUT_PDX_TERRAIN_LOW_SPEC Out;
			Out.WorldSpacePos = Vertex.WorldSpacePos;

			Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );
			Out.ShadowProj = mul( ShadowMapTextureMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );

			CalculateDetailsLowSpec( Vertex.WorldSpacePos.xz, Out.DetailDiffuse, Out.DetailMaterial );

			float2 ColorMapCoords = Vertex.WorldSpacePos.xz * WorldSpaceToTerrain0To1;

#if defined( PDX_OSX ) && defined( PDX_OPENGL )
			// We're limited to the amount of samplers we can bind at any given time on Mac, so instead
			// we disable the usage of ColorTexture (since its effects are very subtle) and assign a
			// default value here instead.
			Out.ColorMap = float3( vec3( 0.5 ) );
#else
			Out.ColorMap = ToLinear( PdxTex2DLod0( ColorTexture, float2( ColorMapCoords.x, 1.0 - ColorMapCoords.y ) ).rgb );
#endif

			Out.FlatMap = float3( vec3( 0.5f ) ); // neutral overlay
			#ifdef TERRAIN_FLAT_MAP_LERP
				Out.FlatMap = lerp( Out.FlatMap, PdxTex2DLod0( FlatMapTexture, float2( ColorMapCoords.x, 1.0 - ColorMapCoords.y ) ).rgb, FlatMapLerp );
			#endif

			Out.Normal = CalculateNormal( Vertex.WorldSpacePos.xz );

			return Out;
		}
	]]

	MainCode VertexShader
	{
		Input = "VS_INPUT_PDX_TERRAIN"
		Output = "VS_OUTPUT_PDX_TERRAIN"
		Code
		[[
			PDX_MAIN
			{
				return TerrainVertex( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );
			}
		]]
	}

	MainCode VertexShaderSkirt
	{
		Input = "VS_INPUT_PDX_TERRAIN_SKIRT"
		Output = "VS_OUTPUT_PDX_TERRAIN"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_TERRAIN Out = TerrainVertex( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );

				float3 Position = FixPositionForSkirt( Out.WorldSpacePos, Input.VertexID );
				Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Position, 1.0 ) );

				return Out;
			}
		]]
	}

	MainCode VertexShaderLowSpec
	{
		Input = "VS_INPUT_PDX_TERRAIN"
		Output = "VS_OUTPUT_PDX_TERRAIN_LOW_SPEC"
		Code
		[[
			PDX_MAIN
			{
				return TerrainVertexLowSpec( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );
			}
		]]
	}

	MainCode VertexShaderLowSpecSkirt
	{
		Input = "VS_INPUT_PDX_TERRAIN_SKIRT"
		Output = "VS_OUTPUT_PDX_TERRAIN_LOW_SPEC"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_TERRAIN_LOW_SPEC Out = TerrainVertexLowSpec( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );

				float3 Position = FixPositionForSkirt( Out.WorldSpacePos, Input.VertexID );
				Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Position, 1.0 ) );

				return Out;
			}
		]]
	}
}


PixelShader =
{
	# PdxTerrain uses texture index 0 - 6

	# Jomini specific
	TextureSampler ShadowMap
	{
		Ref = PdxShadowmap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		CompareFunction = less_equal
		SamplerType = "Compare"
	}

	# Game specific
	TextureSampler FogOfWarAlpha
	{
		Ref = JominiFogOfWar
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler FlatMapTexture
	{
		Ref = TerrainFlatMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	TextureSampler EnvironmentMap
	{
		Ref = JominiEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler FlatMapEnvironmentMap
	{
		Ref = FlatMapEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler SurroundFlatMapMask
	{
		Ref = SurroundFlatMapMask
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Border"
		SampleModeV = "Border"
		Border_Color = { 1 1 1 1 }
		File = "gfx/map/surround_map/surround_mask.dds"
	}

	Code
	[[
		// Switch for the one optimisation in this file. Comment it out to get
		// the plain sharp-terrain behaviour back.
		//
		// TERRAINOPT_SKIP_HIDDEN_TERRAIN
		//   Once the realm colour overlay is fully opaque (zoom step
		//   NTerrainCulling.REALM_COLOR_MAP_FULLY_ZOOM_STEP and beyond) the
		//   terrain surface underneath it is not visible at all. Vanilla
		//   already skips the sun lighting and the fog there, but still
		//   samples the colormap, the heightmap normal and the snow masks and
		//   throws the result away - and this mod adds a full per pixel
		//   CalculateDetails on top of that. With the switch on, that whole
		//   block is skipped and the overlay is returned directly. The output
		//   is bit identical; only the discarded work goes away.
		#define TERRAINOPT_SKIP_HIDDEN_TERRAIN

		// TERRAINOPT_SNOW_MATERIAL is not defined here: it comes from
		// gfx/FX/sharp_terrain_options.fxh, so that an add-on mod can switch it on by
		// overriding that single file.

		// TERRAINOPT_SNOW_MATERIAL_VANILLA is not defined here either: with the snow
		// option on, the low spec shader draws the cheap snow material below; that define
		// (options file, or shader_debug) switches it to vanilla's ApplySnowMaterialTerrain.

		// The vanilla snow material (dynamic_masks.fxh, ApplySnowMaterialTerrain) at a low
		// spec price. Same masks, same height blend, same frost layer, same look up close;
		// what goes: the sine noise and the derivative work of every SampleNoTile (five
		// per pixel), and the second heightmap read for the mountain term, because the
		// pixel shader already has the world height. The two mask lookups keep two reads
		// each (averaged, see below), the three material lookups become one read each.
		// About 9 texture reads per snow pixel instead of about 14 plus the noise math.
		// The snow texture repeats at its tiling instead of being scrambled by the noise;
		// on a near uniform white texture that is not visible.
		void ApplySnowMaterialTerrainCheap( inout float4 Diffuse, inout float3 Normal, inout float4 Properties, float3 TerrainNormal, in float2 WorldSpacePosXz, in float WorldHeight, in float2 MapCoords, inout float HighlightMask )
		{
			// Snow data. "Never snow here" exits after one read, as in vanilla.
			SSnowEffectData SnowEffectData;
			SnowEffectData._NoSnowMask = 1.0f - PdxTex2D( SnowMaskMap, float2( MapCoords.x, 1.0f - MapCoords.y ) ).r;
			if ( SnowEffectData._NoSnowMask < 0.05f )
			{
				HighlightMask = 0.0f;
				return;
			}
			// GetSnowEffectData without the noise math and without GetHeight. Vanilla's
			// SampleNoTile blends two samples of the mask taken at a per region random
			// offset, and over most of the map that blend is a real mix of the two - which
			// halves the mask's variance and is what keeps the snow cover closed. A single
			// read has the full variance and opens holes in the cover, so two reads at fixed
			// offsets are averaged instead: same statistics, no noise math.
			float2 NoiseCoords = ( MapCoords + vec2( _SnowRandomNumber ) * 0.1f ) * _SnowNoiseTiling;
			float4 SnowMaskColor = 0.5f * ( PdxTex2D( SnowMaskMap, NoiseCoords ) + PdxTex2D( SnowMaskMap, NoiseCoords + float2( 0.37f, 0.61f ) ) );
			SnowEffectData._Noise = SnowMaskColor.b;
			SnowEffectData._Noise3 = SnowMaskColor.g;
			SnowEffectData._Noise2 = SnowMaskColor.b * SnowMaskColor.g;
			SnowEffectData._SnowHemisphere = RemapClamped( 1.0f - MapCoords.y, 0.0f, 1.0f, 0.0f, 1.0f );
			SnowEffectData._Height = RemapClamped( WorldHeight, _SnowTerrainHeightMin, _SnowTerrainHeightMax, 0.0f, 1.0f );

			// Masks, as vanilla; the large scale noise averaged the same way
			float Noise = 1.0f - 0.5f * ( PdxTex2D( SnowMaskMap, MapCoords * 5.0f ).a + PdxTex2D( SnowMaskMap, MapCoords * 5.0f + float2( 0.29f, 0.53f ) ).a );
			float GameSnow = GetWinterSeverityValue( MapCoords );
			float GameSnowMask = smoothstep( _SnowGameMaskMin, _SnowGameMaskMax, GameSnow ) * _SnowGameMaskImpact * Noise;
			float Winter = GetWinterValue();
			Winter = saturate( Winter + GameSnowMask - Winter * GameSnowMask );

			float Snow = GetWinterMask( Winter, MapCoords, _SnowTerrainAreaPosition, _SnowTerrainAreaContrast, _SnowHemispherePosition, _SnowHemisphereContrast, SnowEffectData, GameSnowMask, GameSnowMask );
			float Frost = GetWinterMask( Winter, MapCoords, _FrostTerrainAreaPosition, _FrostTerrainAreaContrast, _FrostHemispherePosition, _FrostHemisphereContrast, SnowEffectData, 0.0f, GameSnowMask );
			float WinterSmoothstep = smoothstep( 0.0f, 0.1f, Winter );
			Frost *= _FrostMultiplier * WinterSmoothstep;
			Snow *= WinterSmoothstep;

			if ( Snow < SKIP_VALUE && Frost < SKIP_VALUE )
			{
				HighlightMask = Snow;
				return;
			}
			// Remove snow from steep angle
			TerrainNormal.y = smoothstep( _SnowAngleRemove, 1.0f, abs( TerrainNormal.y ) );
			Snow = lerp( 0.0f, Snow, TerrainNormal.y );
			HighlightMask = Snow;

			// The snow material: one plain read each instead of SampleNoTile
			float2 SnowUV = CalcDetailUV( WorldSpacePosXz ) * _SnowTextureTiling;
			float4 SnowDiffuse = PdxTex2D( DetailTextures, float3( SnowUV, _SnowTexIndex ) );
			float4 SnowNormalRRxG = PdxTex2D( NormalTextures, float3( SnowUV, _SnowTexIndex ) );
			float3 SnowNormal = UnpackRRxGNormal( SnowNormalRRxG ).xyz;
			float4 SnowProperties = PdxTex2D( MaterialTextures, float3( SnowUV, _SnowTexIndex ) );

			// Terrain material blend, as vanilla
			Diffuse.a = lerp( 0.0f, Diffuse.a, _SnowHeightWeight );
			SnowDiffuse.a = 1.0f - lerp( 1.0f, SnowDiffuse.a, 1.0f - _SnowHeightWeight );
			SnowDiffuse.a *= SnowEffectData._Noise3;
			float2 BlendFactors = CalcHeightBlendFactors( float2( Diffuse.a, SnowDiffuse.a ), float2( 1.0f - Snow, Snow ), DetailBlendRange * _SnowHeightContrast * Snow );

			// Initial Frost Layer
			Diffuse = lerp( Diffuse, SnowDiffuse, Frost );
			Normal = lerp( Normal, SnowNormal, Frost );
			Properties = lerp( Properties, SnowProperties, Frost );

			float BlendValue = BlendFactors.y;
			BlendValue = 1 - pow( 1 - BlendValue, 5 );

			// Add more details to the snow
			float DetailAngleReduction = smoothstep( 0.0f, 0.02f, abs( Normal.y ) );
			DetailAngleReduction = lerp( 0.5f, 0.0f, DetailAngleReduction );
			DetailAngleReduction = clamp( DetailAngleReduction * Snow, 0.0f, 1.0f );
			BlendValue = lerp( BlendValue, 0.0f, DetailAngleReduction );
			BlendValue = BlendValue - smoothstep( 0.25f, 1.0f, SnowEffectData._Noise2 ) * 2.0f;
			BlendValue = max( 0.000001f, BlendValue );

			// Snow Layer
			Diffuse = lerp( Diffuse, SnowDiffuse, BlendValue );
			Normal = lerp( Normal, SnowNormal, BlendValue );
			Properties = lerp( Properties, SnowProperties, BlendValue );
		}

		static const float UNDERWATER_CLIP_OFFSET = 0.00001f;
		static const float TERRAIN_SKIRT_CLIP_OFFSET = 0.01f;
		SLightingProperties GetFlatMapLerpSunLightingProperties( float3 WorldSpacePos, float ShadowTerm )
		{
			SLightingProperties LightingProps;
			LightingProps._ToCameraDir = normalize( CameraPosition - WorldSpacePos );
			LightingProps._ToLightDir = ToSunDir;
			LightingProps._LightIntensity = FlatMapLerpSunDiffuse * 5;
			LightingProps._ShadowTerm = ShadowTerm;
			LightingProps._CubemapIntensity = FlatMapLerpCubemapIntensity;
			LightingProps._CubemapYRotation = FlatMapLerpCubemapYRotation;

			return LightingProps;
		}
		void CheckClipNeeded( float TerrainHeight, float2 MapCoords, float StartColorOverlayHeightBlend )
		{
			#ifdef TERRAIN_SKIRT
				clip( TerrainHeight - TERRAIN_SKIRT_CLIP_OFFSET );
			#endif

			#ifdef UNDERWATER
				// When doing the refraction pass and applying the Color Overlay, skip the parts above the ocean.
				if ( StartColorOverlayHeightBlend > 0.99f )
				{
					clip( _RefractionCullHeight - TerrainHeight );
				}
			#endif
			clip( vec2( 1.0f ) - MapCoords );
		}

	]]

	MainCode PixelShader
	{
		Input = "VS_OUTPUT_PDX_TERRAIN"
		Output = "PDX_COLOR"
		Code
		[[

			PDX_MAIN
			{
				float FullColorOverlayFactor = 0.0f;
				bool IsFullyColorOverlay = false;

				const float2 ColorMapCoords = Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1;
				CheckClipNeeded( Input.WorldSpacePos.y, ColorMapCoords, _StartColorOverlayHeightBlend * _EnabledTerrainCulling );

			#ifndef UNDERWATER
				// Skip terrain rendering below the ocean surface.
				if ( Input.WorldSpacePos.y < UNDERWATER_CLIP_OFFSET && _EnabledTerrainCulling > 0.99f)
				{
					return float4( _UnderwaterTerrainColor.rgb, 0.0f );
				}
			#endif

				float3 FlatMap = float3( 0.5f, 0.5f, 0.5f ); // neutral overlay
				#ifdef TERRAIN_FLAT_MAP_LERP
					FlatMap = lerp( FlatMap, PdxTex2D( FlatMapTexture,
						float2( ColorMapCoords.x, 1.0f - ColorMapCoords.y ) ).rgb,
						FlatMapLerp );
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					float3 BorderColor;
					float BorderPreLightingBlend;
					float BorderPostLightingBlend;
					GetBorderColorAndBlendGame( Input.WorldSpacePos.xz, FlatMap, BorderColor, BorderPreLightingBlend, BorderPostLightingBlend );

					FullColorOverlayFactor = BorderPreLightingBlend + BorderPostLightingBlend;
					FullColorOverlayFactor *= _FullyColorOverlayHeightBlend * _EnabledTerrainCulling;
				#endif
				if ( FullColorOverlayFactor > 0.99f )
				{
					IsFullyColorOverlay = true;
				}

				float4 DetailDiffuse = vec4( 0.0f );
				float3 DetailNormal = float3( 0.0f, 1.0f, 0.0f );
				float4 DetailMaterial = vec4( 0.0f );
				float ShadowTerm = 1.0f;
				if( !IsFullyColorOverlay )
				{
					CalculateDetails( Input.WorldSpacePos.xz, DetailDiffuse, DetailNormal, DetailMaterial );
					ShadowTerm = CalculateShadow( Input.ShadowProj, ShadowMap );
				}

				float FogOfWarAlphaValue = PdxTex2D( FogOfWarAlpha, ColorMapCoords).r;
#if defined( PDX_OSX ) && defined( PDX_OPENGL )
				// We're limited to the amount of samplers we can bind at any given time on Mac, so instead
				// we disable the usage of ColorTexture (since its effects are very subtle) and assign a
				// default value here instead.
				float3 ColorMap = float3( vec3( 0.5f ) );
				float ColorDarken = 1.0f;
#else
				float4 ColorMapSample = ToLinear( PdxTex2D( ColorTexture,
						float2( ColorMapCoords.x, 1.0f - ColorMapCoords.y ) ) );
				float ColorDarken = ColorMapSample.a;
				float3 ColorMap = ColorMapSample.rgb;
#endif

				float SnowHighlight = 0.0f;
				float3 Normal = CalculateNormal( Input.WorldSpacePos.xz );
				#ifndef UNDERWATER
					float3 ReorientedNormal = Normal;
					if( !IsFullyColorOverlay )
					{
						float WaterNormalLerp = 0.0f;
						EffectIntensities ConditionData;
						BilinearSampleProvinceEffectsMask( ColorMapCoords, ConditionData );
						ApplyProvinceEffectsTerrain( ConditionData, DetailDiffuse, DetailNormal, DetailMaterial, Input.WorldSpacePos, WaterNormalLerp );

						// Use the property that only water has lower roughness to adjust the terrain normals to face upward.
						float WaterNormalAdjustment = smoothstep( 0.6f, 1.0f, 1 - DetailMaterial.a);
						WaterNormalLerp = max( WaterNormalLerp, WaterNormalAdjustment);
						float3 ReorientedNormal = ReorientNormal(
							lerp( Normal, float3( 0.0f, 1.0f, 0.0f ), WaterNormalLerp ),
							DetailNormal );

						ApplySnowMaterialTerrain( DetailDiffuse, DetailNormal, DetailMaterial, Normal, Input.WorldSpacePos.xz, ColorMapCoords, SnowHighlight );

						if( ConditionData._Drought > 0.0f || SnowHighlight > 0.0f )
						{
							ShadowTerm = lerp( ShadowTerm + 0.4f , ShadowTerm , ShadowTerm );
						}
					}
				#else
					float3 ReorientedNormal = ReorientNormal( Normal, DetailNormal );
				#endif

				float3 Diffuse = SoftLight( DetailDiffuse.rgb, ColorMap,
					( 1 - DetailMaterial.r ) * COLORMAP_OVERLAY_STRENGTH );

				#ifdef TERRAIN_COLOR_OVERLAY
					LerpBorderColorWithFogOfWarAlphaValue( Diffuse, FogOfWarAlphaValue, BorderColor, BorderPreLightingBlend );
					#ifdef TERRAIN_FLAT_MAP_LERP
						float3 FlatColor;
						GetBorderColorAndBlendGameLerp( Input.WorldSpacePos.xz, FlatMap,
							FlatColor, BorderPreLightingBlend, BorderPostLightingBlend,
							FlatMapLerp );

						FlatMap = lerp( FlatMap, FlatColor,
							saturate( BorderPreLightingBlend + BorderPostLightingBlend ) );
					#endif
					float4 HighlightColor = GetHighlightColor( ColorMapCoords );
					ApplyHighlightColor( Diffuse, HighlightColor );
					CompensateWhiteHighlightColor( Diffuse, HighlightColor, SnowHighlight );
				#endif

				SMaterialProperties MaterialProps = GetMaterialProperties(
					Diffuse,
					ReorientedNormal,
					DetailMaterial.a,
					DetailMaterial.g,
					DetailMaterial.b
				);

				SLightingProperties LightingProps = GetMapLightingProperties( Input.WorldSpacePos, ShadowTerm );
				#ifdef TERRAIN_FLAT_MAP_LERP
					LightingProps._LightIntensity = lerp( TERRAIN_SUNNY_SUN_COLOR * TERRAIN_SUNNY_SUN_INTENSITY, FlatMapLerpSunIntensity * SunDiffuse, FlatMapLerp );
					LightingProps._CubemapIntensity =  lerp( DefaultEnvironmentCubemapIntensity * TERRAIN_SUNNY_IBL_SCALE, FlatMapLerpCubemapIntensity , FlatMapLerp );
					LightingProps._ToLightDir = lerp( ToTerrainSunnySunDir, ToSunDir , FlatMapLerp );
				#endif

				// Calculate combined shadow mask from clouds and shadow tint
				float CloudMask = 0.0f;
				float3 FinalColor = vec3( 0.0f );
				if( !IsFullyColorOverlay )
				{
					CloudMask = GetCloudShadowMask( Input.WorldSpacePos.xz, FogOfWarAlphaValue );
					FinalColor = CalculateTerrainDualScenarioLighting( LightingProps, MaterialProps, CloudMask, EnvironmentMap );
					// Apply shadow tint with cloud interaction for terrain
					FinalColor = ApplyTerrainShadowTintWithClouds( FinalColor, Input.WorldSpacePos.xz, CloudMask, ShadowTerm, ReorientedNormal, Normal );
					float BlendAmount = ( 1.0f - ColorDarken ) * CloudMask; // Combine color mask with cloud coverage
					FinalColor.rgb = ApplyOvercastContrast( FinalColor, BlendAmount );
				}

				#ifdef TERRAIN_COLOR_OVERLAY
				 	float NdotL = saturate( dot( MaterialProps._Normal, LightingProps._ToLightDir ) ) + 1e-5;
					BorderColor *= lerp( max( _WaterZoomedInZoomedOutFactor - 0.4f, 0.4f ), 1.0f, NdotL );
					FinalColor.rgb = lerp( FinalColor.rgb, BorderColor, BorderPostLightingBlend );
					ApplyHighlightColor( FinalColor.rgb, HighlightColor, 0.25f );
					ApplyDiseaseDiffuse( FinalColor, ColorMapCoords );
					ApplyLegendDiffuse( FinalColor, ColorMapCoords );
				#endif

				#ifndef UNDERWATER
					if( !IsFullyColorOverlay )
					{
						FinalColor = ApplyFogOfWar( FinalColor, Input.WorldSpacePos, FogOfWarAlpha );
						FinalColor = ApplyMapDistanceFogWithoutFoW( FinalColor, Input.WorldSpacePos );
					}	
				#endif

				#ifdef TERRAIN_FLAT_MAP_LERP
					float Blend = CalculatePaperTransitionBlend( ColorMapCoords, FlatMapLerp );
					FlatMap = ApplyFlatMapBrightnessAdjustment( FlatMap );
					FinalColor = lerp( FinalColor, FlatMap, Blend );
				#endif

				float Alpha = 1.0f;
				#ifdef UNDERWATER
					Alpha = CompressWorldSpace( Input.WorldSpacePos );
				#endif

				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif
				// DebugReturn( FinalColor, MaterialProps, LightingProps, EnvironmentMap );

				return float4( FinalColor, Alpha );
			}
		]]
	}

	MainCode PixelShaderLowSpec
	{
		Input = "VS_OUTPUT_PDX_TERRAIN_LOW_SPEC"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float FullColorOverlayFactor = 0.0f;
				bool IsFullyColorOverlay = false;

				const float2 ColorMapCoords = Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1;
				CheckClipNeeded( Input.WorldSpacePos.y, ColorMapCoords, _StartColorOverlayHeightBlend);

				float3 DetailDiffuse = Input.DetailDiffuse;
				float4 DetailMaterial = Input.DetailMaterial;
				float3 ColorMap = Input.ColorMap;
				float3 FlatMap = Input.FlatMap;
				float3 Normal = Input.Normal;

				#ifdef TERRAIN_COLOR_OVERLAY
					float3 BorderColor;
					float BorderPreLightingBlend;
					float BorderPostLightingBlend;
					GetBorderColorAndBlendGame( Input.WorldSpacePos.xz, FlatMap, BorderColor, BorderPreLightingBlend, BorderPostLightingBlend );

					FullColorOverlayFactor = BorderPreLightingBlend + BorderPostLightingBlend;
					FullColorOverlayFactor *= _FullyColorOverlayHeightBlend * _EnabledTerrainCulling;
				#endif
				if ( FullColorOverlayFactor > 0.99f )
				{
					IsFullyColorOverlay = true;
				}

				float SnowHighlight = 0.0f;
				#ifndef UNDERWATER
					DetailDiffuse = ApplyDynamicMasksDiffuse( DetailDiffuse, Normal, ColorMapCoords );
				#endif

				float3 Diffuse = SoftLight( DetailDiffuse.rgb, ColorMap, ( 1 - DetailMaterial.r ) * COLORMAP_OVERLAY_STRENGTH );

				#ifdef TERRAIN_COLOR_OVERLAY
					float FogOfWarAlphaValue = PdxTex2D( FogOfWarAlpha, ColorMapCoords).r;
					LerpBorderColorWithFogOfWarAlphaValue( Diffuse, FogOfWarAlphaValue, BorderColor, BorderPreLightingBlend );

					#ifdef TERRAIN_FLAT_MAP_LERP
						float3 FlatColor;
						GetBorderColorAndBlendGameLerp( Input.WorldSpacePos.xz, FlatMap,
							FlatColor, BorderPreLightingBlend, BorderPostLightingBlend,
							FlatMapLerp );
						FlatMap = lerp( FlatMap, FlatColor,
							saturate( BorderPreLightingBlend + BorderPostLightingBlend ) );
					#endif
				#endif

				float3 FinalColor = vec3( 0.0f );
				SMaterialProperties MaterialProps = GetMaterialProperties(
					Diffuse,
					Normal,
					DetailMaterial.a,
					DetailMaterial.g,
					DetailMaterial.b
				);
				float ShadowTerm = 1.0f;
				SLightingProperties LightingProps = GetMapLightingProperties( Input.WorldSpacePos, ShadowTerm );
				if( !IsFullyColorOverlay )
				{
					FinalColor = CalculateTerrainSunLightingLowSpec( MaterialProps, LightingProps );
				}
				#ifndef UNDERWATER
					if( !IsFullyColorOverlay )
					{
						FinalColor = ApplyFogOfWar( FinalColor, Input.WorldSpacePos, FogOfWarAlpha );
						FinalColor = ApplyMapDistanceFog( FinalColor, Input.WorldSpacePos, FogOfWarAlpha );
					}
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					FinalColor.rgb = lerp( FinalColor.rgb, BorderColor, BorderPostLightingBlend );
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					float4 HighlightColor = GetHighlightColor( ColorMapCoords );
					ApplyHighlightColor( FinalColor.rgb, HighlightColor );
					CompensateWhiteHighlightColor( FinalColor.rgb, HighlightColor, SnowHighlight );
				#endif

				#ifdef TERRAIN_FLAT_MAP_LERP
					FinalColor = lerp( FinalColor, FlatMap, FlatMapLerp );
				#endif

				float Alpha = 1.0f;
				#ifdef UNDERWATER
					Alpha = CompressWorldSpace( Input.WorldSpacePos );
				#endif

				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif

				DebugReturn( FinalColor, MaterialProps, LightingProps, EnvironmentMap );
				return float4( FinalColor, Alpha );
			}
		]]
	}

	# Low spec terrain, but with the detail textures sampled per pixel.
	# Takes the plain VS_OUTPUT_PDX_TERRAIN (same vertex shader as the high spec
	# path), so none of the per-vertex detail work of VertexShaderLowSpec runs.
	MainCode PixelShaderLowSpecSharp
	{
		Input = "VS_OUTPUT_PDX_TERRAIN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float FullColorOverlayFactor = 0.0f;
				bool IsFullyColorOverlay = false;

				const float2 ColorMapCoords = Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1;
				CheckClipNeeded( Input.WorldSpacePos.y, ColorMapCoords, _StartColorOverlayHeightBlend );

				float3 FlatMap = float3( 0.5f, 0.5f, 0.5f ); // neutral overlay
				#ifdef TERRAIN_FLAT_MAP_LERP
					FlatMap = lerp( FlatMap, PdxTex2D( FlatMapTexture,
						float2( ColorMapCoords.x, 1.0f - ColorMapCoords.y ) ).rgb,
						FlatMapLerp );
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					float3 BorderColor;
					float BorderPreLightingBlend;
					float BorderPostLightingBlend;
					GetBorderColorAndBlendGame( Input.WorldSpacePos.xz, FlatMap, BorderColor, BorderPreLightingBlend, BorderPostLightingBlend );

					FullColorOverlayFactor = BorderPreLightingBlend + BorderPostLightingBlend;
					FullColorOverlayFactor *= _FullyColorOverlayHeightBlend * _EnabledTerrainCulling;
				#endif
				if ( FullColorOverlayFactor > 0.99f )
				{
					IsFullyColorOverlay = true;
				}

				#if defined( TERRAIN_COLOR_OVERLAY ) && defined( TERRAINOPT_SKIP_HIDDEN_TERRAIN )
					// Everything from here to the sun lighting only feeds
					// CalculateTerrainSunLightingLowSpec, which is already gated on
					// !IsFullyColorOverlay. Take the same exit early instead, so the
					// detail textures, the colormap, CalculateNormal and the snow
					// masks are never sampled for a surface that is fully covered.
					if ( IsFullyColorOverlay )
					{
						float OverlayPost = BorderPostLightingBlend;
						float3 OverlayFlatMap = FlatMap;
						#ifdef TERRAIN_FLAT_MAP_LERP
							// Matches the main path, where the Lerp variant overwrites
							// BorderPostLightingBlend before it is used below.
							float3 OverlayFlatColor;
							float OverlayPre;
							GetBorderColorAndBlendGameLerp( Input.WorldSpacePos.xz, FlatMap,
								OverlayFlatColor, OverlayPre, OverlayPost, FlatMapLerp );
							OverlayFlatMap = lerp( FlatMap, OverlayFlatColor,
								saturate( OverlayPre + OverlayPost ) );
						#endif

						float3 OverlayColor = lerp( vec3( 0.0f ), BorderColor, OverlayPost );

						float4 OverlayHighlight = GetHighlightColor( ColorMapCoords );
						ApplyHighlightColor( OverlayColor, OverlayHighlight );
						// SnowHighlight is never written in this shader, so it is 0 here too.
						CompensateWhiteHighlightColor( OverlayColor, OverlayHighlight, 0.0f );

						#ifdef TERRAIN_FLAT_MAP_LERP
							OverlayColor = lerp( OverlayColor, OverlayFlatMap, FlatMapLerp );
						#endif

						float OverlayAlpha = 1.0f;
						#ifdef UNDERWATER
							OverlayAlpha = CompressWorldSpace( Input.WorldSpacePos );
						#endif

						#ifdef TERRAIN_DEBUG
							TerrainDebug( OverlayColor, Input.WorldSpacePos );
						#endif

						return float4( OverlayColor, OverlayAlpha );
					}
				#endif

				// The one actual change: per pixel detail sampling, with proper
				// mip selection, instead of the per vertex CalculateDetailsLowSpec.
				float4 DetailDiffuseHeight = vec4( 0.0f );
				float3 DetailNormal = float3( 0.0f, 1.0f, 0.0f );
				float4 DetailMaterial = vec4( 0.0f );
				if ( !IsFullyColorOverlay )
				{
					CalculateDetails( Input.WorldSpacePos.xz, DetailDiffuseHeight, DetailNormal, DetailMaterial );
				}
				float3 DetailDiffuse = DetailDiffuseHeight.rgb;

#if defined( PDX_OSX ) && defined( PDX_OPENGL )
				// Same sampler count limit workaround as the high spec pixel shader.
				float3 ColorMap = float3( vec3( 0.5f ) );
#else
				float3 ColorMap = ToLinear( PdxTex2D( ColorTexture,
						float2( ColorMapCoords.x, 1.0f - ColorMapCoords.y ) ).rgb );
#endif

				float SnowHighlight = 0.0f;
				float3 Normal = CalculateNormal( Input.WorldSpacePos.xz );
				#ifndef UNDERWATER
					#ifdef TERRAINOPT_SNOW_MATERIAL
						// The snow material blends into the detail height, normal and
						// material as well, so snow gets its own normals and roughness,
						// and SnowHighlight feeds the white highlight compensation below.
						#ifdef TERRAINOPT_SNOW_MATERIAL_VANILLA
							ApplySnowMaterialTerrain( DetailDiffuseHeight, DetailNormal, DetailMaterial, Normal, Input.WorldSpacePos.xz, ColorMapCoords, SnowHighlight );
						#else
							ApplySnowMaterialTerrainCheap( DetailDiffuseHeight, DetailNormal, DetailMaterial, Normal, Input.WorldSpacePos.xz, Input.WorldSpacePos.y, ColorMapCoords, SnowHighlight );
						#endif
						DetailDiffuse = DetailDiffuseHeight.rgb;
					#else
						DetailDiffuse = ApplyDynamicMasksDiffuse( DetailDiffuse, Normal, ColorMapCoords );
					#endif
				#endif

				// Detail normal maps are sampled by CalculateDetails anyway, so using
				// them is free. Comment this out for flat vanilla low spec shading.
				float3 ReorientedNormal = ReorientNormal( Normal, DetailNormal );

				float3 Diffuse = SoftLight( DetailDiffuse.rgb, ColorMap, ( 1 - DetailMaterial.r ) * COLORMAP_OVERLAY_STRENGTH );

				#ifdef TERRAIN_COLOR_OVERLAY
					float FogOfWarAlphaValue = PdxTex2D( FogOfWarAlpha, ColorMapCoords).r;
					LerpBorderColorWithFogOfWarAlphaValue( Diffuse, FogOfWarAlphaValue, BorderColor, BorderPreLightingBlend );

					#ifdef TERRAIN_FLAT_MAP_LERP
						float3 FlatColor;
						GetBorderColorAndBlendGameLerp( Input.WorldSpacePos.xz, FlatMap,
							FlatColor, BorderPreLightingBlend, BorderPostLightingBlend,
							FlatMapLerp );
						FlatMap = lerp( FlatMap, FlatColor,
							saturate( BorderPreLightingBlend + BorderPostLightingBlend ) );
					#endif
				#endif

				float3 FinalColor = vec3( 0.0f );
				SMaterialProperties MaterialProps = GetMaterialProperties(
					Diffuse,
					ReorientedNormal,
					DetailMaterial.a,
					DetailMaterial.g,
					DetailMaterial.b
				);
				float ShadowTerm = 1.0f;
				SLightingProperties LightingProps = GetMapLightingProperties( Input.WorldSpacePos, ShadowTerm );
				if( !IsFullyColorOverlay )
				{
					FinalColor = CalculateTerrainSunLightingLowSpec( MaterialProps, LightingProps );
				}
				#ifndef UNDERWATER
					if( !IsFullyColorOverlay )
					{
						FinalColor = ApplyFogOfWar( FinalColor, Input.WorldSpacePos, FogOfWarAlpha );
						FinalColor = ApplyMapDistanceFog( FinalColor, Input.WorldSpacePos, FogOfWarAlpha );
					}
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					FinalColor.rgb = lerp( FinalColor.rgb, BorderColor, BorderPostLightingBlend );
				#endif

				#ifdef TERRAIN_COLOR_OVERLAY
					float4 HighlightColor = GetHighlightColor( ColorMapCoords );
					ApplyHighlightColor( FinalColor.rgb, HighlightColor );
					CompensateWhiteHighlightColor( FinalColor.rgb, HighlightColor, SnowHighlight );
				#endif

				#ifdef TERRAIN_FLAT_MAP_LERP
					FinalColor = lerp( FinalColor, FlatMap, FlatMapLerp );
				#endif

				float Alpha = 1.0f;
				#ifdef UNDERWATER
					Alpha = CompressWorldSpace( Input.WorldSpacePos );
				#endif

				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif

				DebugReturn( FinalColor, MaterialProps, LightingProps, EnvironmentMap );
				return float4( FinalColor, Alpha );
			}
		]]
	}

	MainCode PixelShaderFlatMap
	{
		Input = "VS_OUTPUT_PDX_TERRAIN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				#ifdef TERRAIN_SKIRT
					return float4( 0, 0, 0, 0 );
				#endif

				clip( vec2( 1.0f ) - Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1 );

				float2 ColorMapCoords = Input.WorldSpacePos.xz * WorldSpaceToTerrain0To1;
				float3 FlatMap = PdxTex2D( FlatMapTexture, float2( ColorMapCoords.x, 1.0 - ColorMapCoords.y ) ).rgb;


				#ifdef TERRAIN_COLOR_OVERLAY
					float3 BorderColor;
					float BorderPreLightingBlend;
					float BorderPostLightingBlend;

					GetBorderColorAndBlendGameLerp( Input.WorldSpacePos.xz, FlatMap,
						BorderColor, BorderPreLightingBlend, BorderPostLightingBlend,
						1.0f );

					FlatMap = lerp( FlatMap, BorderColor,
						saturate( BorderPreLightingBlend + BorderPostLightingBlend ) );

				#endif

				float3 FinalColor = FlatMap;
				#ifdef TERRAIN_COLOR_OVERLAY
					float4 HighlightColor = GetHighlightColor( ColorMapCoords );
					ApplyHighlightColor( FinalColor, HighlightColor, 0.5f );
				#endif

				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif

				FinalColor = ApplyFlatMapBrightnessAdjustment( FinalColor );

				// Make flatmap transparent based on the SurroundFlatMapMask
				float SurroundMapAlpha = 1 - PdxTex2D( SurroundFlatMapMask, float2( ColorMapCoords.x, 1.0 - ColorMapCoords.y ) ).b;
				SurroundMapAlpha *= FlatMapLerp;

				return float4( FinalColor, SurroundMapAlpha );
			}
		]]
	}
}


Effect PdxTerrain
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"

	Defines = { "TERRAIN_FLAT_MAP_LERP" }
}

Effect PdxTerrainLowSpec
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderLowSpecSharp"
}

Effect PdxTerrainSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShader"
	Defines = { "TERRAIN_SKIRT" }
}

Effect PdxTerrainLowSpecSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShaderLowSpecSharp"
	Defines = { "TERRAIN_SKIRT" }
}

### FlatMap Effects

BlendState BlendStateAlpha
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
}

Effect PdxTerrainFlat
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderFlatMap"
	BlendState = BlendStateAlpha

	Defines = { "TERRAIN_FLAT_MAP" "TERRAIN_FLATMAP_LIGHTING" }
}

Effect PdxTerrainFlatSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShaderFlatMap"
	BlendState = BlendStateAlpha

	Defines = { "TERRAIN_FLAT_MAP" "TERRAIN_SKIRT" }
}

# Low Spec flat map the same as regular effect
Effect PdxTerrainFlatLowSpec
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderFlatMap"
	BlendState = BlendStateAlpha

	Defines = { "TERRAIN_FLAT_MAP" }
}

Effect PdxTerrainFlatLowSpecSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShaderFlatMap"
	BlendState = BlendStateAlpha

	Defines = { "TERRAIN_FLAT_MAP" "TERRAIN_SKIRT" }
}
