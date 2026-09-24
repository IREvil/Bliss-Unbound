#ifdef VOXY_PATCH
    #undef GENERATED_NORMALS
    #undef COATED_TEXTURES
    #undef CUSTOM_PBR
    #ifndef IPBR_COMPAT_MODE
        #define IPBR_COMPAT_MODE
    #endif
#endif

#ifdef IPBR
    vec3 maRecolor = vec3(0.0);
    #include "/lib/materials/materialHandling/terrainIPBR.glsl"

    #ifdef GENERATED_NORMALS
        // le perfecto bliss: GenerateNormals clips its four neighbour samples
        // against the sprite bounds (midCoord +/- absMidCoordPos).  Bliss
        // derives those from mc_midTexCoord via vtexcoordam, and in this host
        // that comes back as zero -- which collapses the bounds onto the
        // fragment and rejects every sample, so the normal is never updated and
        // the surface renders perfectly flat.  Widen them for the call: the
        // sample offset is a fraction of a texel, so a permissive bound costs at
        // most one texel of bleed at a sprite edge and nothing anywhere else.
        if (!noGeneratedNormals) {
            vec2 ipbrSavedAbsMidCoordPos = absMidCoordPos;
            vec2 ipbrSavedMidCoordPos = midCoordPos;
            absMidCoordPos = vec2(0.5);
            midCoordPos = vec2(0.0);
            // GetDif subtracts the neighbour sample from the passed-in colour, so
            // both sides must come from the same sampling path.  colorP comes
            // from Bliss' 3-arg POM-switch sampler (explicit LOD) while the four
            // neighbours use a plain 2-arg fetch (implicit LOD); if those resolve
            // to different mip levels the difference is a near-constant that the
            // 0.05 threshold discards and every GetDif returns exactly 0.  Hand
            // it a plain sample at texCoord instead -- that is precisely what the
            // debug_TEXTURE_GRADIENT diagnostic does, and it demonstrably
            // produces gradients.
            vec3 ipbrSavedColorP = colorP;
            colorP = texture2D(tex, texCoord).rgb;
            GenerateNormals(normalM, colorP);
            colorP = ipbrSavedColorP;
            absMidCoordPos = ipbrSavedAbsMidCoordPos;
            midCoordPos = ipbrSavedMidCoordPos;
        }
    #endif

    #ifdef COATED_TEXTURES
        CoatTextures(color.rgb, noiseFactor, playerPos, doTileRandomisation);
    #endif

    #if IPBR_EMISSIVE_MODE != 1 && !defined VOXY_PATCH
        emission = GetCustomEmissionForIPBR(color, glColor, emission);
    #endif
#else
    #ifdef CUSTOM_PBR
        GetCustomMaterials(color, normalM, lmCoordM, NdotU, shadowMult, smoothnessG, smoothnessD, highlightMult, emission, materialMask, viewPos, lViewPos);
    #endif

    if (mat == 10001) { // No directional shading
        noDirectionalShading = true;
    } else if (mat == 10005) { // Grounded Waving Foliage
        subsurfaceMode = 1, noSmoothLighting = true, noDirectionalShading = true;
        #if defined GBUFFERS_TERRAIN || defined VOXY_PATCH
            DoFoliageColorTweaks(color.rgb, shadowMult, snowMinNdotU, viewPos, nViewPos, lViewPos, dither);
        #endif
    } else if (mat == 10009 || mat == 10011) { // Leaves
        #include "/lib/materials/specificMaterials/terrain/leaves.glsl"
    } else if (mat == 10017) { // Non-waving Foliage
        subsurfaceMode = 1, noSmoothLighting = true, noDirectionalShading = true;
    } else if (mat == 10021) { // Upper Waving Foliage
        subsurfaceMode = 1, noSmoothLighting = true, noDirectionalShading = true;
        #if defined GBUFFERS_TERRAIN || defined VOXY_PATCH
            DoFoliageColorTweaks(color.rgb, shadowMult, snowMinNdotU, viewPos, nViewPos, lViewPos, dither);
        #endif
    } else if (mat == 10028) { // Modded Light Sources
        noSmoothLighting = true; noDirectionalShading = true;
        emission = GetLuminance(color.rgb) * 2.5;
    } else if (mat == 11009) { // Vine, Pale Hanging Moss
        subsurfaceMode = 3, centerShadowBias = true; noSmoothLighting = true;
    }

    #ifdef SNOWY_WORLD
    else if (mat == 10132) { // Grass Block:Normal
        if (glColor.b < 0.999) { // Grass Block:Normal:Grass Part
            snowMinNdotU = min(pow2(pow2(color.g)) * 1.9, 0.1);
            color.rgb = color.rgb * 0.5 + 0.5 * (color.rgb / glColor.rgb);
        }
    }
    #endif

    else if (lmCoord.x > 0.99999) lmCoordM.x = 0.95;
#endif
