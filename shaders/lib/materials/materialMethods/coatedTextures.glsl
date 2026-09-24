const float packSizeNT = 64.0;

void CoatTextures(inout vec3 color, float noiseFactor, vec3 playerPos, bool doTileRandomisation) {
    #ifndef ENTITY_GN_AND_CT
        #if defined GBUFFERS_ENTITIES || defined GBUFFERS_HAND
            return;
        #endif
    #endif

    // midCoordPos reads as zero in this host (see generatedNormals.glsl); rebuild it from the 16px atlas grid.
    vec2 spriteSizeUV = vec2(16.0) / max(atlasSizeM, vec2(1.0));
    vec2 midCoordPosG = texCoord - (floor(texCoord / spriteSizeUV) + 0.5) * spriteSizeUV;

    #ifndef SAFER_GENERATED_NORMALS
        vec2 noiseCoord = floor(midCoordPosG / 16.0 * packSizeNT * atlasSizeM) / packSizeNT / 3.0;
    #else
        vec2 noiseCoord = floor(midCoordPosG / spriteSizeUV * packSizeNT) / packSizeNT / 3.0;
    #endif

    if (doTileRandomisation) {
        vec3 floorWorldPos = floor(playerPos + cameraPosition + 0.001);
        noiseCoord += 0.84 * (floorWorldPos.xz + floorWorldPos.y);
    }

    // Complementary's noisetex is white noise; Bliss' noisetex is smooth at this scale, so hash the cell instead.
    vec2 noiseCell = mod(floor(noiseCoord * packSizeNT * 3.0 + 0.5), 4096.0);
    float noiseTexture = fract(sin(dot(noiseCell, vec2(12.9898, 78.233))) * 43758.5453);
    noiseTexture = noiseTexture + 0.6;
    float colorBrightness = dot(color, color) * 0.3;
    #define COATED_TEXTURE_MULT_M COATED_TEXTURE_MULT * 0.0027
    noiseFactor *= COATED_TEXTURE_MULT_M * max0(1.0 - colorBrightness);
    noiseFactor *= max(1.0 - miplevel * 0.25, 0.0);
    noiseTexture = pow(noiseTexture, noiseFactor);
    color *= noiseTexture;
}
