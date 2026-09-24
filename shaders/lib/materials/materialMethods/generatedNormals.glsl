const float normalThreshold = 0.05;
const float normalClamp = 0.2;

// le perfecto bliss: normalMult used to be declared here, at file scope, as a
// non-const global initialised from a macro.  It has been moved inside
// GenerateNormals as a local.  Every other value this file contributes to the
// program is a const or a local; this one created a program-scope variable with
// a runtime initialiser, present in every shader that includes the file whether
// or not the function ever runs.
//
// (Strength history: upstream uses 0.025.  A lower base of 0.010 was tried to
// keep full-strength gradients inside the +-1 clamp, but it only reduced the
// relief that was working and left the hard texture-edge pattern untouched, so
// the strength is not what drives that pattern and lowering it is a net loss.)

float GetDif(float lOriginalAlbedo, vec2 offsetCoord) {
    #ifndef GBUFFERS_WATER
        // Explicit LOD 0.  An implicit-LOD sample lets the camera decide which
        // mipmap is read: dead-on the footprint is tiny so it reads mip 0 and the
        // gradients are clean, but at an angle the footprint grows, a higher mip
        // is selected, and atlas filtering there blends neighbouring pixels and
        // even neighbouring sprites.  Those false colour transitions get read as
        // geometry, which is the hard pattern that tracks the texture, depends
        // purely on view direction, flips light/dark with the sun, and is immune
        // to GENERATED_NORMAL_MULT -- because the samples change, not the scale.
        vec4 nearbySample = texture2D(tex, offsetCoord);
        // Cutout neighbours carry no height; reading their black rgb bevels every edge and makes coplanar
        // overlays (redstone dot + lines) disagree, which z-fights.
        if (nearbySample.a < 0.1) return 0.0;
        float lNearbyAlbedo = length(nearbySample.rgb);
    #else
        vec4 textureSample = texture2D(tex, offsetCoord);
        float lNearbyAlbedo = length(textureSample.rgb * textureSample.a * 1.5);
    #endif

    #ifdef GBUFFERS_ENTITIES
        lOriginalAlbedo = abs(lOriginalAlbedo - 1.0);
        lNearbyAlbedo = abs(lNearbyAlbedo - 1.0);
    #endif

    float dif = lOriginalAlbedo - lNearbyAlbedo;

    #ifdef GBUFFERS_ENTITIES
        dif = -dif;
    #endif

    #ifndef GBUFFERS_WATER
        if (dif > 0.0) dif = max(dif - normalThreshold, 0.0);
        else           dif = min(dif + normalThreshold, 0.0);
    #endif

    return clamp(dif, -normalClamp, normalClamp);
}

void GenerateNormals(inout vec3 normalM, vec3 color) {
    #ifndef ENTITY_GN_AND_CT
        #if defined GBUFFERS_ENTITIES || defined GBUFFERS_HAND
            return;
        #endif
    #endif

    // -----------------------------------------------------------------------
    // Diagnostic switch, enabled from the shaderpack options file with
    //     GN_TEST_CONSTNORMAL=true
    // so it can be toggled without rebuilding the pack.
    //
    // Forces a single constant view-space normal (pointing to the right of the
    // camera) and returns before any sampling, tangent or maths runs.
    //
    //   world changes dramatically -> the call executes, inout writes through
    //       to the global normalM, and normalM reaches the G-buffer.  Anything
    //       upstream of the sampling is fine.
    //   nothing changes -> the function is not being called, is compiled out,
    //       its inout write does not reach normalM, or normalM is overwritten
    //       afterwards.  Every theory about sampling, LOD, tangents and offsets
    //       becomes irrelevant.
    //
    // This is the test that settles item #1 of GENERATED-NORMALS-REPORT.md: a
    // constant normal cannot produce a texture-tracing lighting pattern, so if
    // the mesh survives this, it is not produced by the normal at all.
    // -----------------------------------------------------------------------
    #ifndef GBUFFERS_HAND
        float normalMult = GENERATED_NORMAL_MULT * 0.025;
    #else
        float normalMult = GENERATED_NORMAL_MULT * 0.015;
    #endif

    #ifdef GN_TEST_CONSTNORMAL
        normalM = vec3(1.0, 0.0, 0.0);
        return;
    #endif

    vec2 absMidCoordPos2 = absMidCoordPos * 2.0;
    float lOriginalAlbedo = length(color.rgb);

    #ifndef SAFER_GENERATED_NORMALS
        vec2 offsetR = 16.0 / atlasSizeM;
    #else
        vec2 offsetR = max(absMidCoordPos2.x, absMidCoordPos2.y) * vec2(float(atlasSizeM.y) / float(atlasSizeM.x), 1.0);
    #endif
    offsetR /= GENERATED_NORMAL_RES;

    vec2 originalOffsetR = offsetR;
    offsetR = max(originalOffsetR, ipbrTexCoordFwidth);

    // le perfecto bliss: reconstruct the sprite bounds from the atlas grid.
    //
    // The four bound gates below exist so a sample near a sprite edge does not
    // read into the NEIGHBOURING sprite in the atlas.  They had been defused to
    // +-1e9 because absMidCoordPos reads as zero in this host and the collapsed
    // bounds rejected every sample -- but with the bounds gone, fragments within
    // 0.125 texels of a sprite edge sample a different sprite, so their gradient
    // disagrees with the interior.  That is a rim around every block texture:
    // the grid visible on snow, and block edges not meeting their neighbours.
    // Raising GENERATED_NORMAL_MULT amplifies it, because the rim is a real
    // discontinuity in the normal rather than a shading artefact.
    //
    // The atlas is a regular grid of vanilla 16px sprites and atlasSizeM is
    // reliable, so both the centre and the half-size are computable from
    // texCoord without absMidCoordPos.
    //
    // NOTE: this assumes 16px sprites.  A resource pack with larger block
    // textures would make the grid wrong and the gates too tight, fading
    // generated normals out; deriving the sprite size would be the fix there.
    vec2 spriteSizeUV = vec2(16.0) / max(atlasSizeM, vec2(1.0));
    vec2 spriteCentre = (floor(texCoord / spriteSizeUV) + 0.5) * spriteSizeUV;
    vec2 spriteHalf = 0.5 * spriteSizeUV;
    vec2 maxOffsetCoord = spriteCentre + spriteHalf;
    vec2 minOffsetCoord = spriteCentre - spriteHalf;

    vec3 normalMap = vec3(0.0, 0.0, 1.0);

    vec2 offsetCoord = texCoord + vec2(0.0, offsetR.y);
    if (offsetCoord.y < maxOffsetCoord.y)
        normalMap.y += GetDif(lOriginalAlbedo, offsetCoord);

    offsetCoord = texCoord + vec2(offsetR.x, 0.0);
    if (offsetCoord.x < maxOffsetCoord.x)
        normalMap.x += GetDif(lOriginalAlbedo, offsetCoord);

    offsetCoord = texCoord + vec2(0.0, -offsetR.y);
    if (offsetCoord.y > minOffsetCoord.y)
        normalMap.y -= GetDif(lOriginalAlbedo, offsetCoord);

    offsetCoord = texCoord + vec2(-offsetR.x, 0.0);
    if (offsetCoord.x > minOffsetCoord.x)
        normalMap.x -= GetDif(lOriginalAlbedo, offsetCoord);

    normalMap.xy *= vec2(normalMult * sqrt(GENERATED_NORMAL_RES / 128.0)) * (originalOffsetR / offsetR);
    normalMap.xy = clamp(normalMap.xy, vec2(-1.0), vec2(1.0));

    // le perfecto bliss: report what THIS function actually computed.  Every
    // previous diagnostic was a replica standing beside the real thing, which is
    // how the bound-gate discrepancy went unnoticed for several rounds.  This is
    // written from inside the function the shader calls.
    //   x = lOriginalAlbedo   y = normalMap.x   z = normalMap.y   w = 1 (ran)
    ipbrGNDebug = vec4(lOriginalAlbedo, normalMap.x, normalMap.y, 1.0);

    // dot() rather than an exact vector comparison: same intent, and no corner case.
    if (dot(normalMap.xy, normalMap.xy) > 1e-10)
        normalM = clamp(normalize(ipbrTbnMatrix * normalMap), vec3(-1.0), vec3(1.0));
}
