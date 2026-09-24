// ===========================================================================
//  IntegratedPBR+ settings and derived defines
//  Ported from Complementary Unbound r5.9.1 (lib/common.glsl) by le perfecto bliss
//
//  The user-facing sliders live in /lib/settings.glsl.  This file only turns
//  them into the macros the transplanted material library expects, so the
//  material files themselves can stay byte-identical to upstream.
// ===========================================================================

#ifndef IPBR_SETTINGS_INCLUDED
#define IPBR_SETTINGS_INCLUDED

// ---------------------------------------------------------------------------
//  Master switch
// ---------------------------------------------------------------------------
//  IPBR_MODE 0 -> Bliss' original LabPBR resource-pack material pipeline
//  IPBR_MODE 1 -> Complementary's IntegratedPBR+ material database
#if IPBR_MODE == 1
    #define IPBR
    #define IPBR_PARTICLE_FEATURES
    #define MORE_REFLECTIVE_DISTANT_GLASS
    #define FANCY_GLASS
    // Upstream keys several shared branches off RP_MODE; 1 is its IPBR mode.
    #ifndef RP_MODE
        #define RP_MODE 1
    #endif
    #if defined MATERIAL_AO
        #undef MATERIAL_AO
    #endif
#endif

// Complementary calls the block sampler `tex`; Bliss calls it `texture`.
#ifndef tex
    #define tex texture
#endif

// Minimum opacity the glass material gives the empty part of a pane
// (upstream: GLASS_OPACITY 0.25).  This is what makes upstream glass read as a
// pale surface rather than a hole; lower it to make glass more see-through.
#ifndef GLASS_OPACITY
    #define GLASS_OPACITY IPBR_GLASS_OPACITY * 0.01
#endif

#ifdef IPBR_COMPAT_MODE_DEFINE
    #define IPBR_COMPAT_MODE
#endif

#ifdef GREEN_SCREEN_LIME_DEFINE
    #define GREEN_SCREEN_LIME
#endif

// ---------------------------------------------------------------------------
//  Glowing ores / glowing stuff
//  GLOWING_ORE_MASTER: 0 = off, 2 = all, 1 = the "Complementary" preset set
// ---------------------------------------------------------------------------
#if GLOWING_ORE_MASTER == 2 || GLOWING_ORE_MASTER == 1
    #define GLOWING_ORE_IRON
    #define GLOWING_ORE_GOLD
    #define GLOWING_ORE_COPPER
    #define GLOWING_ORE_REDSTONE
    #define GLOWING_ORE_LAPIS
    #define GLOWING_ORE_EMERALD
    #define GLOWING_ORE_DIAMOND
    #define GLOWING_ORE_NETHERQUARTZ
    #define GLOWING_ORE_NETHERGOLD
    #define GLOWING_ORE_GILDEDBLACKSTONE
    #define GLOWING_ORE_ANCIENTDEBRIS
    #define GLOWING_ORE_MODDED
#endif

#if GLOWING_AMETHYST > 0
    #define GLOWING_AMETHYST_I GLOWING_AMETHYST
#endif
#if GLOWING_LICHEN > 0
    #define GLOWING_LICHEN_I GLOWING_LICHEN
#endif

// Percentage sliders are integers in the GUI; upstream multiplies by 0.01.
#define GENERATED_NORMAL_MULT_M GENERATED_NORMAL_MULT * 0.01
#define NORMAL_MAP_STRENGTH_M NORMAL_MAP_STRENGTH * 0.01
#define CUSTOM_EMISSION_INTENSITY_M CUSTOM_EMISSION_INTENSITY * 0.01
// Complementary emission runs 0..~4 and adds linearly; Bliss mixes to albedo*5 by pow(E, Emissive_Curve).
#define IpbrToBlissEmission(e) clamp(pow(max((e) * IPBR_EMISSION_STRENGTH * 0.01, 0.0), 1.0 / Emissive_Curve), 0.0, 254.0 / 255.0)

// Generated normals and coated textures both sample the block texture against
// an offset tangent basis, so they need at_tangent even when the resource pack
// provides no normal maps.  Complementary forces it the same way.
#if defined IPBR && (defined GENERATED_NORMALS || defined COATED_TEXTURES)
    #define IPBR_NEEDS_TANGENT

    // ----------------------------------------------------------------------

    // Complementary applies these two to entities and the held item as well.
    #ifndef ENTITY_GN_AND_CT
        #define ENTITY_GN_AND_CT
    #endif
#endif

// MIRROR_TINTED_GLASS and friends are plain 0..100 sliders.
#if MIRROR_TINTED_GLASS > 0
    #define MIRROR_TINTED_GLASS_M MIRROR_TINTED_GLASS * 0.01
#endif

// ---------------------------------------------------------------------------
//  Program identification
//  Complementary keys its material tables off GBUFFERS_*; Bliss keys off
//  WORLD / ENTITIES / HAND / BLOCKENTITIES in /dimensions/all_solid.*.
// ---------------------------------------------------------------------------
#if defined WORLD && !defined ENTITIES && !defined HAND && !defined BLOCKENTITIES
    #define GBUFFERS_TERRAIN
#endif
#if defined ENTITIES && !defined HAND
    #define GBUFFERS_ENTITIES
#endif
#ifdef HAND
    #define GBUFFERS_HAND
#endif
#if defined BLOCKENTITIES && !defined HAND
    #define GBUFFERS_BLOCK
#endif
#ifdef WATER
    #define GBUFFERS_WATER
#endif

// Complementary gates a handful of branches behind its own quality knobs.
// Bliss has no equivalents, so pin them to the values its defaults assume.
#ifndef SHADOW_QUALITY
    #define SHADOW_QUALITY 2
#endif
#ifndef POM_QUALITY
    #define POM_QUALITY 128
#endif
#ifndef POM_LIGHTING_MODE
    #define POM_LIGHTING_MODE 2
#endif
#ifndef RAIN_PUDDLES
    #define RAIN_PUDDLES 0
#endif
#ifndef DIRECTIONAL_BLOCKLIGHT
    #define DIRECTIONAL_BLOCKLIGHT 0
#endif
#ifndef WATER_REFLECT_QUALITY
    #define WATER_REFLECT_QUALITY 2
#endif
#ifndef VOXY_PATCH
    #define IPBR_NO_VOXY
#endif

// We never want upstream's texture-space POM inside the IPBR path: Bliss owns
// parallax occlusion mapping on its LabPBR path, and IPBR mode has no
// heightmap to trace.
#if defined IPBR && defined POM
    #undef POM
#endif
#if defined IPBR && defined MC_NORMAL_MAP && defined IPBR_DISABLE_NORMAL_MAPS
    #undef MC_NORMAL_MAP
#endif

// ---------------------------------------------------------------------------
//  Specular strength
//
//  Complementary expresses specular intensity as a multiplier (`highlightMult`)
//  applied to the OUTPUT of a GGX highlight that internally uses a fixed
//  Fresnel of 0.05.  Bliss instead feeds F0 straight into its Fresnel term and
//  its reflection mix, so copying the multiplier into F0 linearly over-brightens
//  at normal incidence -- glass at highlightMult 3.5 would land on F0 0.175,
//  nearly 9x Bliss' own 0.02 for reflective blocks, and blows the sun highlight
//  out into a white smear.
//
//  A square root keeps the material ordering while staying in a sane range:
//      highlightMult 1.0 -> 0.050      (Complementary's constant)
//      highlightMult 1.5 -> 0.061      stained glass
//      highlightMult 2.0 -> 0.071      obsidian, iron
//      highlightMult 3.5 -> 0.094      glass, quartz
//      highlightMult 5.0 -> 0.112
// ---------------------------------------------------------------------------
#ifndef IPBR_SPECULAR_STRENGTH
    #define IPBR_SPECULAR_STRENGTH 100
#endif
#define IPBR_SPECULAR_STRENGTH_M IPBR_SPECULAR_STRENGTH * 0.01

// Scales the opacity the translucent table resolved.  Stained glass has no
// GLASS_OPACITY floor upstream, so this is the only knob that reaches it.
#ifndef IPBR_TRANSLUCENT_ALPHA
    #define IPBR_TRANSLUCENT_ALPHA 100
#endif
#define IPBR_TRANSLUCENT_ALPHA_M IPBR_TRANSLUCENT_ALPHA * 0.01

// Complementary's "Intense Fresnel" (materialMask 1) covers iron, quartz,
// obsidian, amethyst, diamond, emerald and deepslate.  Upstream it swaps the
// Fresnel curve for `fresnelM * 0.75 + 0.25` (deferred1.glsl) -- a 0.25
// reflectance floor even head-on.  100 reproduces that floor exactly; scale up
// for a more mirror-like metal, down for a softer sheen.
#ifndef IPBR_INTENSE_FRESNEL_MULT
    #define IPBR_INTENSE_FRESNEL_MULT 100
#endif
#define IPBR_INTENSE_FRESNEL_MULT_M IPBR_INTENSE_FRESNEL_MULT * 0.01

// ---------------------------------------------------------------------------
//  Water
//
//  Water is the one thing IntegratedPBR+ does not reduce to a material lookup.
//  Upstream, `specificMaterials/translucents/water.glsl` is a complete water
//  renderer -- its own colour model, wave normals, foam, absorbance, fog and
//  (with world-space reflections) reflections.  Bliss already has its own
//  water, and this port keeps it:
//
//    * translucent water (id 32000) never enters the IPBR table
//    * the water cauldron branch in terrainIPBR.glsl is fenced behind
//      IPBR_COMPLEMENTARY_WATER, which is off unless you ask for it
//
//  Set IPBR_WATER_MATERIAL 1 to hand water over to Complementary's version.
//  That path needs upstream's water configuration, supplied below, because
//  several of those macros are read as `#if WATER_STYLE < 3` style tests where
//  an undefined macro silently evaluates to 0 -- i.e. a non-default look.
// ---------------------------------------------------------------------------
#if IPBR_WATER_MATERIAL == 1
    #define IPBR_COMPLEMENTARY_WATER

    // Complementary's own defaults (its SHADER_STYLE 4 profile).
    #ifndef WATER_STYLE
        #define WATER_STYLE 3
    #endif
    #ifndef WATERCOLOR_MODE
        #define WATERCOLOR_MODE 3
    #endif
    #ifndef SUN_MOON_STYLE
        #define SUN_MOON_STYLE 2
    #endif
    #ifndef WATER_ALPHA_MULT
        #define WATERCOLOR_R 100
        #define WATERCOLOR_G 100
        #define WATERCOLOR_B 100
        #define WATERCOLOR_RM WATERCOLOR_R * 0.01
        #define WATERCOLOR_GM WATERCOLOR_G * 0.01
        #define WATERCOLOR_BM WATERCOLOR_B * 0.01

        #define WATER_ALPHA_MULT 100
        #define WATER_FOG_MULT 100
        #define WATER_FOAM_I 100
        #define WATER_BUMPINESS 1.25
        #define WATER_BUMP_SMALL 0.75
        #define WATER_BUMP_MED 1.70
        #define WATER_BUMP_BIG 2.00
        #define WATER_SPEED_MULT 1.10
        #define WATER_SIZE_MULT 100
        #define WATER_ALPHA_MULT_M WATER_ALPHA_MULT * 0.01
        #define WATER_FOG_MULT_M WATER_FOG_MULT * 0.01
        #define WATER_FOAM_IM WATER_FOAM_I * 0.01
        #define WATER_SPEED_MULT_M WATER_SPEED_MULT
        #define WATER_SIZE_MULT_M WATER_SIZE_MULT * 0.01
        #define WATER_BUMPINESS_M WATER_BUMPINESS
        #define WATER_BUMPINESS_M2 WATER_BUMPINESS_M * WATER_BUMPINESS_M
    #endif

    #define BRIGHT_CAVE_WATER
    #define WATER_REFRACTION
#endif

#endif // IPBR_SETTINGS_INCLUDED
