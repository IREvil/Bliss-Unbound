// World-space reflections on the ACT scene volume.
// Voxel data and the ray march are upstream's; shading at the hit uses Bliss' light terms.

#if COLORED_LIGHTING_INTERNAL > 0 && WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && !defined INCLUDE_BLISS_WSR
#define INCLUDE_BLISS_WSR

uniform usampler3D wsr_sampler;
uniform usampler3D wsr_lod_sampler;
uniform sampler2D textureAtlas;

vec3 previousCameraPositionBestFract = fract(previousCameraPosition);

#include "/lib/voxelization/reflectionVoxelization.glsl"

// Set by the host each fragment before specularReflections runs.
vec3 wsrSunColor = vec3(0.0);
vec3 wsrAmbientColor = vec3(0.0);
vec3 wsrSunDir = vec3(0.0, 1.0, 0.0);
// 1 = day (and other dimensions), 0 = night; picks WSR_DAY/NIGHT_STRENGTH.
float wsrDayFactor = 1.0;
// Distance along the ray of the last WSR hit, -1 on a miss.
float wsrHitDist = -1.0;
// The reflection pass' resolution scale (1 = full), for the hit texture's LOD.
float wsrLodScale = 1.0;
// The deferred translucent resolve turns this off: the water pass already traced the player against SSR.
bool wsrTracePlayer = true;

#include "/lib/voxelization/playerRef.glsl"

vec2 WsrLocalTexCoord(vec3 local, vec3 normal) {
    vec3 absNormal = abs(normal);
    return 1.0 - local.zy * absNormal.x - local.xz * absNormal.y - local.xy * absNormal.z;
}

float WsrVoxelAO(ivec3 voxelPos, ivec3 normal, vec2 localTexCoord) {
    ivec3 absNormal = abs(normal);
    ivec3 hrz = ivec3(0, 0, 1) * absNormal.x + ivec3(1, 0, 0) * absNormal.y + ivec3(1, 0, 0) * absNormal.z;
    ivec3 vrt = ivec3(0, 1, 0) * absNormal.x + ivec3(0, 0, 1) * absNormal.y + ivec3(0, 1, 0) * absNormal.z;

    vec2 dir = 1.0 - 2.0 * localTexCoord;
    ivec2 signDir = ivec2(sign(dir));
    ivec3 voxelHrz = voxelPos + normal + signDir.x * hrz;
    ivec3 voxelVrt = voxelPos + normal + signDir.y * vrt;

    vec2 factor = dir * dir;
    float occHrz = mix(1.0, float(texelFetch(wsr_sampler, voxelHrz, 0).r == 0u), factor.x);
    float occVrt = mix(1.0, float(texelFetch(wsr_sampler, voxelVrt, 0).r == 0u), factor.y);

    return 0.3 * (occHrz + occVrt) + 0.4;
}

// Sun visibility at a hit from Bliss' shadow map; -1 when the hit is outside it.
float WsrSunShadow(vec3 playerPos, vec3 normal) {
    #ifdef OVERWORLD_SHADER
        vec3 shadowPos = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
        float biasDistance = 1.0 + length(shadowPos.xy) * (128.0 / shadowDistance) * 0.1;
        shadowPos += (mat3(shadowModelView) * normal) * (shadowDistance / shadowMapResolution * 4.0) * 0.15 * biasDistance;
        shadowPos = diagonal3(shadowProjection) * shadowPos + shadowProjection[3].xyz;
        #ifdef DISTORT_SHADOWMAP
            shadowPos.xy *= calcDistort(shadowPos.xy);
        #endif
        if (abs(shadowPos.x) > 1.0 || abs(shadowPos.y) > 1.0 || abs(shadowPos.z) > 6.0) return -1.0;
        shadowPos.z += shadowProjection[3].z * 0.0012;
        shadowPos = shadowPos * vec3(0.5, 0.5, 0.5 / 6.0) + 0.5;
        return shadow2D(shadow, shadowPos).x;
    #else
        return -1.0;
    #endif
}

vec4 WsrShade(ivec3 voxelPos, vec3 playerPos, vec3 normal, vec3 rayStart, vec3 rayDir) {
    faceData face = getFaceData(voxelPos, normal);
    if (face.textureBounds.z < 1e-6) return vec4(-1.0);

    vec2 localTexCoord = WsrLocalTexCoord(fract(playerPos + cameraPositionBestFract), normal);
    vec2 atlas = vec2(textureSize(textureAtlas, 0));
    vec2 textureRad = face.textureBounds.z * vec2(1.0, atlas.x / atlas.y);

    // Complementary blurs the hit texture by how large it projects on screen (worldSpaceRef.glsl): the further the
    // reflection travelled, the softer it reads. That is what makes a rough surface look rough now that the ray
    // itself is exact, so without it every reflection came out mirror-sharp.
    float virtualDist = length(playerPos - rayStart) + length(rayStart);
    float textureFactor = length(textureRad * atlas) * 3.0;
    float lod = 0.5 * log2(max(virtualDist * textureFactor / gbufferProjection[0][0] / max(abs(dot(normal, rayDir)), 0.05) / (1.0 / texelSize.y) / wsrLodScale, 1e-6));
    lod *= REFLECTION_BLUR * 0.01;
    vec4 color = texture2DLod(textureAtlas, face.textureBounds.xy + 2.0 * textureRad * localTexCoord, max(lod, 0.0));
    if (color.a < 0.0041) return vec4(-1.0);

    vec3 albedo = toLinear(color.rgb * face.glColor);
    vec2 lm = face.lightmap;

    float NdotL = max(dot(normal, wsrSunDir), 0.0);
    float sunVisibility = 0.0;
    if (NdotL > 0.0) {
        float sunShadow = WsrSunShadow(playerPos, normal);
        sunVisibility = sunShadow < 0.0 ? pow(lm.y, 8.0) : sunShadow * smoothstep(0.0, 0.25, lm.y);
    }
    vec3 direct = wsrSunColor * NdotL * sunVisibility;

    float skyCurve = (pow(lm.y, 15.0) * 2.0 + lm.y * lm.y) / 3.0;
    vec3 ambient = wsrAmbientColor * skyCurve * ambient_brightness * ((normal.y + 1.0) * 0.25 + 0.5);

    float blockCurve = 1.0 - sqrt(1.0 - clamp(lm.x, 0.0, 1.0));
    blockCurve *= blockCurve;
    vec3 blockColor = vec3(TORCH_R, TORCH_G, TORCH_B);
    vec3 voxelPosM = clamp01(SceneToVoxel(playerPos + normal * 0.5) / vec3(voxelVolumeSize));
    vec3 actLight = sqrt(max(GetLightVolume(voxelPosM).rgb, vec3(0.0)));
    blockColor = GetLuminance(blockColor) * DoLuminanceCorrection(actLight + blockColor * 0.05) * (COLORED_LIGHT_STRENGTH / 1300.0);
    vec3 block = blockColor * blockCurve * TORCH_AMOUNT;

    float ao = WsrVoxelAO(voxelPos, ivec3(normal), localTexCoord);

    vec3 fadeout = smoothstep(0.0, 32.0, 0.5 * vec3(sceneVoxelVolumeSize) - abs(playerPos));
    float alpha = sqrt3(minOf(fadeout)) * 0.9 + 0.1;

    vec3 lit = albedo * (direct + ambient + block) * ao;

    // Upstream runs its IPBR table at the hit; approximate its emission: light blocks glow by texel
    // brightness, glowing ores by texel saturation. Blended the way Bliss' Emission() does.
    int mat = int(texelFetch(wsr_sampler, voxelPos, 0).r);
    int lightId = GetVoxelIDs(mat);
    float emit = 0.0;
    bool ore = mat == 10616 || mat == 10624;
    #if GLOWING_ORE_MASTER > 0
        ore = ore || mat == 10252 || mat == 10272 || mat == 10276 || mat == 10284 || mat == 10288 || mat == 10300 || mat == 10304
                  || mat == 10308 || mat == 10320 || mat == 10324 || mat == 10340 || mat == 10344 || mat == 10356 || mat == 10360
                  || mat == 10368 || mat == 10484 || mat == 10612 || mat == 10620;
    #endif
    if (ore) emit = smoothstep(0.12, 0.35, maxOf(color.rgb) - minOf(color.rgb)) * GLOWING_ORE_MULT * 0.5;
    else if (lightId > 1 && lightId < 200) emit = GetLuminance(color.rgb);
    if (emit > 0.0) lit = mix(lit, albedo * 5.0 * Emissive_Brightness, clamp(pow(emit, Emissive_Curve), 0.0, 1.0));

    return vec4(lit, alpha);
}

vec4 WsrTrace(vec3 playerPos, vec3 voxelPos, vec3 rayDir) {
    // A zero component gives 0/0 and 0*inf step distances, which freeze the march (GPU hang).
    vec3 raySign = mix(vec3(1.0), sign(rayDir), notEqual(rayDir, vec3(0.0)));
    rayDir = raySign * max(abs(rayDir), vec3(1e-5));

    vec3 stepAxis = vec3(0.0);
    vec3 stepDir = sign(rayDir);
    vec3 stepSizes = 1.0 / abs(rayDir);

    float dist1 = 0.0;
    vec3 voxelPosRT1 = voxelPos * 0.25;
    vec3 nextDist1 = (stepDir * 0.5 + 0.5 - fract(voxelPosRT1)) / rayDir;

    for (int i1 = 0; i1 < 256 && CheckInsideLodVoxelVolume(voxelPosRT1); i1++) {
        if (texelFetch(wsr_lod_sampler, ivec3(voxelPosRT1), 0).r > 0u) {
            float dist0 = 0.0;
            vec3 voxelPosRT0 = playerToSceneVoxel(playerPos + (4.0 * dist1 - 0.001) * rayDir);
            vec3 nextDist0 = (stepDir * 0.5 + 0.5 - fract(voxelPosRT0)) / rayDir;

            vec3 lodVoxelMin = floor(voxelPosRT1) * 4.0;
            vec3 lodVoxelMax = lodVoxelMin + 4.0;
            float maxDist0 = minOf((mix(lodVoxelMin, lodVoxelMax, stepDir * 0.5 + 0.5) - voxelPosRT0) / rayDir);

            for (int i0 = 0; i0 < 16 && dist0 < maxDist0 && CheckInsideSceneVoxelVolume(voxelPosRT0); i0++) {
                if (texelFetch(wsr_sampler, ivec3(voxelPosRT0), 0).r > 0u) {
                    float traceLength = 4.0 * dist1 + dist0;
                    vec3 normal = -stepAxis * stepDir;
                    vec3 intersection = playerPos + (traceLength - 0.001) * rayDir;

                    vec4 reflection = WsrShade(ivec3(voxelPosRT0), intersection, normal, playerPos, rayDir);
                    if (reflection.a > -0.5) {
                        wsrHitDist = traceLength;
                        return reflection;
                    }
                }

                dist0 = minOf(nextDist0);
                stepAxis = vec3(equal(nextDist0, vec3(dist0)));
                nextDist0 += stepAxis * stepSizes;
                voxelPosRT0 += stepAxis * stepDir;
            }
        }

        dist1 = minOf(nextDist1);
        stepAxis = vec3(equal(nextDist1, vec3(dist1)));
        nextDist1 += stepAxis * stepSizes;
        voxelPosRT1 += stepAxis * stepDir;
    }

    return vec4(0.0);
}

// playerPos: camera-relative feet position; worldNormal and rayDir in world space.
vec4 BlissWSR(vec3 playerPos, vec3 worldNormal, vec3 rayDir) {
    wsrHitDist = -1.0;
    playerPos += 0.04 * worldNormal;
    vec3 voxelPos = playerToSceneVoxel(playerPos);
    if (!CheckInsideSceneVoxelVolume(voxelPos)) {
        wsrHitDist = -2.0; // no WSR coverage here
        return vec4(0.0);
    }
    vec4 reflection = WsrTrace(playerPos, voxelPos, rayDir);

    #ifdef INCLUDE_PLAYER_REF
        if (wsrTracePlayer) {
            vec4 playerRef = BlissPlayerRef(playerPos, rayDir, wsrHitDist > 0.0 ? wsrHitDist : 999999.0, wsrSunColor, wsrAmbientColor, wsrSunDir);
            if (playerRef.a > 0.0) {
                wsrHitDist = playerRefHitDist;
                return playerRef;
            }
        }
    #endif

    return reflection;
}

#endif
