// Player in world-space reflections. The player is not in the voxel volume; world0's shadow pass records its quads
// and skin (Complementary's player tracer) and composite3 clears the bounds again.
// Needs the ACT light volume (lightVoxelization.glsl) and uniform eyeBrightnessSmooth from the host.

#if COLORED_LIGHTING_INTERNAL > 0 && WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && WORLD_SPACE_PLAYER_REF == 1 && defined PLAYER_REF_TRACE && !defined INCLUDE_PLAYER_REF
#define INCLUDE_PLAYER_REF

#ifndef SSBO_QUALIFIER
    #define SSBO_QUALIFIER readonly
#endif
#include "/lib/voxelization/SSBOs/playerVerticesBuffer.glsl"

uniform sampler2D playerAtlas_sampler;
uniform bool is_invisible;

#include "/lib/materials/materialMethods/playerRayTracer.glsl"

// Distance along the ray of the last player hit.
float playerRefHitDist = -1.0;

#ifndef INCLUDE_BLISS_WSR
    // Same host-set light terms as blissWSR.glsl.
    vec3 wsrSunColor = vec3(0.0);
    vec3 wsrAmbientColor = vec3(0.0);
    vec3 wsrSunDir = vec3(0.0, 1.0, 0.0);
#endif

// limit: distance of whatever the ray already hit (the player must be in front of it).
vec4 BlissPlayerRef(vec3 playerPos, vec3 rayDir, float limit, vec3 sunColor, vec3 ambientColor, vec3 sunDir) {
    playerRefHitDist = -1.0;
    if (is_invisible) return vec4(0.0);

    vec3 albedo, normal;
    if (!rayTracePlayer(playerPos - 0.01 * rayDir, rayDir, limit, albedo, normal)) return vec4(0.0);
    playerRefHitDist = playerTraceDist;
    if (dot(normal, rayDir) > 0.0) normal = -normal;

    // The player's own light: the camera's sky and block light.
    vec2 lm = clamp(vec2(eyeBrightnessSmooth) / 240.0, 0.0, 1.0);

    vec3 direct = sunColor * max(dot(normal, sunDir), 0.0) * pow(lm.y, 8.0);
    float skyCurve = (pow(lm.y, 15.0) * 2.0 + lm.y * lm.y) / 3.0;
    vec3 ambient = ambientColor * skyCurve * ambient_brightness * ((normal.y + 1.0) * 0.25 + 0.5);

    float blockCurve = 1.0 - sqrt(1.0 - lm.x);
    blockCurve *= blockCurve;
    vec3 blockColor = vec3(TORCH_R, TORCH_G, TORCH_B);
    vec3 actLight = sqrt(max(GetLightVolume(clamp01(SceneToVoxel(vec3(0.0)) / vec3(voxelVolumeSize))).rgb, vec3(0.0)));
    blockColor = GetLuminance(blockColor) * DoLuminanceCorrection(actLight + blockColor * 0.05) * (COLORED_LIGHT_STRENGTH / 1300.0);

    return vec4(toLinear(albedo) * (direct + ambient + blockColor * blockCurve * TORCH_AMOUNT), 1.0);
}

#endif
