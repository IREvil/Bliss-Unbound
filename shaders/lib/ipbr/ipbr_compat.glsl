// ===========================================================================
//  IntegratedPBR+ compatibility layer
//
//  Complementary's material library expects a specific set of globals and
//  helpers to already exist by the time it is included (upstream they are
//  provided by lib/common.glsl and program/gbuffers_terrain.glsl).  Bliss has
//  none of them, so this file supplies the missing half of the contract.
//
//  Helpers below are copied from Complementary Unbound r5.9.1
//  (lib/util/commonFunctions.glsl, lib/util/dither.glsl,
//   program/gbuffers_terrain.glsl, program/gbuffers_entities.glsl)
//  with only cosmetic changes.  See CREDITS.txt.
// ===========================================================================

#ifndef IPBR_COMPAT_INCLUDED
#define IPBR_COMPAT_INCLUDED

// Every helper below reads at least one of the IPBR globals, so the whole file
// is only meaningful when IntegratedPBR+ is the active material system.
#ifdef IPBR

// Shared, environment-free helpers (constants, pow2/sqrt1 family, colour
// probes, Bayer dithering).
#include "/lib/ipbr/ipbr_math.glsl"


// ---------------------------------------------------------------------------
//  Program-level material tweaks
//  (Complementary program/gbuffers_terrain.glsl)
// ---------------------------------------------------------------------------
void DoFoliageColorTweaks(inout vec3 color, inout vec3 shadowMult, inout float snowMinNdotU,
                          vec3 viewPos, vec3 nViewPos, float lViewPos, float dither) {
    float factor = max(80.0 - lViewPos, 0.0);
    shadowMult *= 1.0 + 0.004 * noonFactor * factor;

    #if defined IPBR && !defined IPBR_COMPAT_MODE
        color.rgb *= 0.97 - 0.2 * signMidCoordPos.x;
    #endif

    #ifdef SNOWY_WORLD
        if (glColor.g - glColor.b > 0.01)
            snowMinNdotU = min(pow2(pow2(max0(color.g * 2.0 - color.r - color.b))) * 5.0, 0.1);
        else
            snowMinNdotU = min(pow2(pow2(max0(color.g * 2.0 - color.r - color.b))) * 3.0, 0.1) * 0.25;
    #endif
}

void DoBrightBlockTweaks(vec3 color, float minLight, inout vec3 shadowMult, inout float highlightMult) {
    float factor = mix(minLight * 0.5 + 0.5, 1.0, pow2(pow2(color.r)));
    shadowMult = vec3(factor);
    highlightMult /= factor;
}

void DoOceanBlockTweaks(inout float smoothnessD) {
    smoothnessD *= max0(lmCoord.y - 0.95) * 20.0;
}

// ---------------------------------------------------------------------------
//  Generated normals and coated textures
//
//  Both are Complementary's materialMethods, used verbatim.  The one thing they
//  need that the host already has is the texture-space derivative: Bliss
//  computes dcdx/dcdy at file scope in all_solid.fsh with its own mip bias, so
//  rather than pull in Complementary's lib/util/miplevel.glsl -- which would
//  redeclare them -- the equivalent globals (midCoordPos, atlasSizeM, miplevel)
//  are derived from Bliss' values in ipbr_solid.glsl before these are called.
// ---------------------------------------------------------------------------
#ifdef GENERATED_NORMALS
    #ifndef IPBR_GENERATED_NORMALS_INCLUDED
        #define IPBR_GENERATED_NORMALS_INCLUDED
        #include "/lib/materials/materialMethods/generatedNormals.glsl"
    #endif
#endif

#ifdef COATED_TEXTURES
    #ifndef IPBR_COATED_TEXTURES_INCLUDED
        #define IPBR_COATED_TEXTURES_INCLUDED
        #include "/lib/materials/materialMethods/coatedTextures.glsl"
    #endif
#endif

// ---------------------------------------------------------------------------
//  Armour hiding (Complementary program/gbuffers_entities.glsl)
//
//  Upstream these consult Iris' `relativeEyePosition` / `isElytraFlying` to
//  hide only the *main player's* armour.  Those uniforms are not used anywhere
//  else in Bliss, and getting their declared types wrong would be an Iris
//  compile error, so the calls are compiled out entirely while HIDE_ARMOR is 0
//  (upstream's default).  Set HIDE_ARMOR > 0 only if you also port the checks.
// ---------------------------------------------------------------------------
void HideArmor(inout vec4 color, vec3 playerPos) { color.a = 0.0; }
void HideArmorDontSkip(inout vec4 color, vec3 playerPos) { color.a = 0.0; }
void HideElytra(inout vec4 color, vec3 playerPos) { color.a = 0.0; }

// ---------------------------------------------------------------------------
//  Resource-pack emission override for IPBR (upstream includes this whenever
//  IPBR_EMISSIVE_MODE asks for it; it does not compile under mode 1).
// ---------------------------------------------------------------------------
#if IPBR_EMISSIVE_MODE != 1
    #include "/lib/materials/materialMethods/customEmission.glsl"
#endif


// Needs the noisetex sampler, so it lives here rather than in ipbr_math.glsl.
float Noise3D(vec3 p) {
    p.z = fract(p.z) * 128.0;
    float iz = floor(p.z);
    float fz = fract(p.z);
    vec2 a_off = vec2(23.0, 29.0) * (iz) / 128.0;
    vec2 b_off = vec2(23.0, 29.0) * (iz + 1.0) / 128.0;
    float a = texture2DLod(noisetex, p.xy + a_off, 0.0).r;
    float b = texture2DLod(noisetex, p.xy + b_off, 0.0).r;
    return mix(a, b, fz);
}

#endif // IPBR
#endif // IPBR_COMPAT_INCLUDED
