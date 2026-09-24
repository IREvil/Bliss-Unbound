#version 330 compatibility
#extension GL_ARB_explicit_attrib_location: enable
#extension GL_ARB_shader_image_load_store: enable

#include "/lib/settings.glsl"

#define RENDER_SHADOW


/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/

#if defined IS_LPV_ENABLED || COLORED_LIGHTING_INTERNAL > 0
	attribute vec4 mc_Entity;
	#ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
		attribute vec4 at_midBlock;
	#else
		attribute vec3 at_midBlock;
	#endif
	attribute vec3 vaPosition;

	uniform mat4 shadowModelViewInverse;
	
	uniform int renderStage;
	uniform vec3 chunkOffset;
	uniform vec3 cameraPosition;
    uniform int currentRenderedItemId;
	uniform int blockEntityId;
	uniform int entityId;

	#include "/lib/blocks.glsl"
	#include "/lib/entities.glsl"
	#include "/lib/items.glsl"
	#include "/lib/ipbr/ipbr_settings.glsl"
	#include "/lib/ipbr/id_decode.glsl"
#endif

#ifdef IS_LPV_ENABLED
	#include "/lib/voxel_common.glsl"
	#include "/lib/voxel_write.glsl"
#endif

// Complementary's ACT light volume.  Separate from Bliss' LPV above; the two are
// mutually exclusive (see the IS_LPV_ENABLED gate in settings.glsl), so at most
// one of these two branches is ever active.
#if COLORED_LIGHTING_INTERNAL > 0
	layout(r16ui) uniform writeonly uimage3D voxel_img;
	uniform usampler3D voxel_sampler;
	uniform sampler3D floodfill_sampler;
	uniform sampler3D floodfill_sampler_copy;
	uniform int framemod2;
	// Iris 1.8+ can supply cameraPositionFract, but it is not declared in every
	// program, and this must compile wherever the voxeliser is used.  fract of
	// cameraPosition is equivalent and always available.
	vec3 cameraPositionBestFract = fract(cameraPosition);

	// lightVoxelization.glsl gates its write entry point on these, which
	// Complementary's shadow program defines for itself.  Scoped to the include
	// and undone after, so they cannot change how Bliss' code below compiles.
	#define VERTEX_SHADER
	#define SHADOW
	#include "/lib/voxelization/act_common.glsl"
	#include "/lib/voxelization/lightVoxelization.glsl"
	#undef SHADOW
	#undef VERTEX_SHADER
#endif


void main() {
	#if defined IS_LPV_ENABLED && defined MC_GL_EXT_shader_image_load_store
		#ifdef LPV_NOSHADOW_HACK
			vec3 playerpos = gl_Vertex.xyz;
		#else
			vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
			vec3 playerpos = mat3(shadowModelViewInverse) * position + shadowModelViewInverse[3].xyz;
		#endif

		PopulateShadowVoxel(playerpos);
	#endif

	// ACT light volume write.  mat is Iris' block id, which is what the
	// ported lightVoxelization table is keyed on.
	//
	// Deliberately OUTSIDE the LPV guard above: ACT and Bliss' LPV are
	// mutually exclusive, so nesting this inside IS_LPV_ENABLED compiled the
	// write away whenever ACT was on, leaving the volume empty here.
	#if COLORED_LIGHTING_INTERNAL > 0
		UpdateVoxelMap(int(mc_Entity.x + 0.5));
	#endif

	gl_Position = vec4(-1.0);

	#if ACT_DEBUG_BREAK_SHADOW == 1
		// Diagnostics: clip EVERYTHING off-screen so no shadow is cast at all.
		gl_Position = vec4(3.0, 3.0, 3.0, 1.0);
	#endif
}
