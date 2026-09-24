// ===========================================================================
//  ACT floodfill
//
//  Ported from Complementary's program/shadowcomp.glsl.  This is the pass that
//  actually spreads light through the voxel volume: each invocation reads the
//  previous frame's neighbours, sums them, and writes the result back, ping-
//  ponging between floodfill_img and floodfill_img_copy every frame
//  (framemod2 selects which is which).
//
//  Emissive blocks enter here as voxel ids >= 200, and GetSpecialBlocklightColor
//  turns those into coloured light -- which is why torches, lanterns, candles
//  and portals only light the world once this pass runs.  Without it the volume
//  holds block ids but no light ever propagates out of them.
//
//  Upstream gates the whole file on SHADOWCOMP; here the host calls
//  DoActFloodfill() from its own main().
// ===========================================================================

#if COLORED_LIGHTING_INTERNAL > 0

#ifndef INCLUDE_ACT_FLOODFILL
#define INCLUDE_ACT_FLOODFILL

// Declared before the includes below: lightVoxelization.glsl's read path
// (GetComplexLightVolume) references these, and GLSL needs every identifier
// declared before use, even inside functions this pass never calls.
uniform sampler3D floodfill_sampler;
uniform sampler3D floodfill_sampler_copy;

#include "/lib/colors/blocklightColors.glsl"
#include "/lib/voxelization/lightVoxelization.glsl"

// Work-group count lives in the host program: Iris parses it as a directive and needs a
// literal ivec3 constructor, so it cannot be computed here.


#ifdef OPTIMIZATION_ACT_SHARED_MEMORY
	shared vec4 sharedLight[10][10][10];
#endif

vec4 GetLightSample(sampler3D lightSampler, ivec3 pos) {
	#ifdef OPTIMIZATION_ACT_SHARED_MEMORY
		ivec3 localPos = pos - ivec3(gl_WorkGroupID) * ivec3(8); // global -> local
		if (all(greaterThanEqual(localPos, ivec3(0))) && all(lessThan(localPos, ivec3(8)))) {
			return sharedLight[localPos.x][localPos.y][localPos.z];
		} else {
			return texelFetch(lightSampler, pos, 0); // fallback to global fetch
		}
	#else
		return texelFetch(lightSampler, pos, 0);
	#endif
}

vec4 GetLightCalculated(sampler3D lightSampler, ivec3 pos, ivec3 voxelVolumeSize, uint voxel) {
	vec4 light_px = GetLightSample(lightSampler, clamp(pos + ivec3( 1,  0,  0), ivec3(0), voxelVolumeSize - 1));
	vec4 light_py = GetLightSample(lightSampler, clamp(pos + ivec3( 0,  1,  0), ivec3(0), voxelVolumeSize - 1));
	vec4 light_pz = GetLightSample(lightSampler, clamp(pos + ivec3( 0,  0,  1), ivec3(0), voxelVolumeSize - 1));
	vec4 light_nx = GetLightSample(lightSampler, clamp(pos + ivec3(-1,  0,  0), ivec3(0), voxelVolumeSize - 1));
	vec4 light_ny = GetLightSample(lightSampler, clamp(pos + ivec3( 0, -1,  0), ivec3(0), voxelVolumeSize - 1));
	vec4 light_nz = GetLightSample(lightSampler, clamp(pos + ivec3( 0,  0, -1), ivec3(0), voxelVolumeSize - 1));

	vec4 light = light_px + light_py + light_pz + light_nx + light_ny + light_nz;
	light /= 6.42; // Slightly higher than 6 to prevent the light from travelling too far

	if (voxel >= 200u) {
		vec3 tint = specialTintColor[min(voxel - 200u, specialTintColor.length() - 1u)];
		light.rgb *= tint;
		light.a *= dot(tint, vec3(0.333333));
	}

	return light;
}

void DoActFloodfill() {
	ivec3 pos = ivec3(gl_GlobalInvocationID);
	vec3 posM = vec3(pos) / vec3(voxelVolumeSize);
	vec3 posOffset = floor(previousCameraPosition) - floor(cameraPosition);
	ivec3 previousPos = pos - ivec3(posOffset);
	ivec3 localPos = ivec3(gl_LocalInvocationID);

	#ifdef OPTIMIZATION_ACT_SHARED_MEMORY
		vec4 prevLight = vec4(0.0);
		if (int(framemod2) == 0)
			prevLight = texelFetch(floodfill_sampler, previousPos, 0);
		else
			prevLight = texelFetch(floodfill_sampler_copy, previousPos, 0);

		sharedLight[localPos.x][localPos.y][localPos.z] = prevLight;

		barrier();

		ivec3 alignedOffset = ivec3(posOffset) / 8 * 8;
		previousPos = pos - alignedOffset;
	#endif

	// Skip work for voxels behind the camera; they are not visible this frame.
	// Only safe to leave stale when coloured light fog is off, which is the same
	// condition upstream uses.
	#ifdef OPTIMIZATION_ACT_BEHIND_PLAYER
		ivec3 absPosFromCenter = abs(pos - voxelVolumeSize / 2);
		if (absPosFromCenter.x + absPosFromCenter.y + absPosFromCenter.z > 16) {
			vec4 viewPos = gbufferProjectionInverse * vec4(0.0, 0.0, 1.0, 1.0);
			viewPos /= viewPos.w;
			vec3 nPlayerPos = normalize(mat3(gbufferModelViewInverse) * viewPos.xyz);
			if (dot(normalize(posM - 0.5), nPlayerPos) < 0.0) {
				#ifdef COLORED_LIGHT_FOG
					if (int(framemod2) == 0) {
						imageStore(floodfill_img_copy, pos, GetLightSample(floodfill_sampler, previousPos));
					} else {
						imageStore(floodfill_img, pos, GetLightSample(floodfill_sampler_copy, previousPos));
					}
				#endif
				return;
			}
		}
	#endif

	vec4 light = vec4(0.0);
	uint rawData = GetVoxelVolumeRaw(pos);
	uint voxel = rawData & 32767u;
	uint isColorwheelGeometry = (rawData - voxel) >> 15u;

	if (voxel == 1u) { // Solid Blocks
		light = vec4(0.0);
	} else if (voxel == 0u || voxel >= 200u) { // Air, Non-solids, Translucents
		if (int(framemod2) == 0) {
			#ifdef OPTIMIZATION_ACT_HALF_RATE_SPREADING
				if (posM.z > 0.5) light = GetLightSample(floodfill_sampler, previousPos);
				else
			#endif
			light = GetLightCalculated(floodfill_sampler, previousPos, voxelVolumeSize, voxel);
		} else {
			#ifdef OPTIMIZATION_ACT_HALF_RATE_SPREADING
				if (posM.z < 0.5) light = GetLightSample(floodfill_sampler_copy, previousPos);
				else
			#endif
			light = GetLightCalculated(floodfill_sampler_copy, previousPos, voxelVolumeSize, voxel);
		}
	} else { // Light Sources
		vec4 color = GetSpecialBlocklightColor(int(voxel));
		if (isColorwheelGeometry == 1u) color.a = 1.0;
		light = max(light, vec4(pow2(color.rgb), color.a));
	}

	light = clamp(light, vec4(0.0), vec4(1000.0)); // Prevents a random NaN from consuming the volume

	if (int(framemod2) == 0) {
		imageStore(floodfill_img_copy, pos, light);
	} else {
		imageStore(floodfill_img, pos, light);
	}
}

#endif // INCLUDE_ACT_FLOODFILL
#endif // COLORED_LIGHTING_INTERNAL > 0
