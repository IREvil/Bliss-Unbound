// ===========================================================================
//  IntegratedPBR+ -- shared environment
//
//  Complementary's material library reads its inputs from file-scope globals
//  (declared in lib/common.glsl and lib/uniforms.glsl) and writes its results
//  to the same.  These declarations are the Bliss-side half of that contract.
//
//  They live at file scope, not inside main(), because several helper
//  functions in ipbr_compat.glsl reference them.
//
//  Include order in a program:
//      ipbr_settings.glsl  ->  ipbr_globals.glsl  ->  ipbr_compat.glsl
//  ...and finally ipbr_solid.glsl inside main().
// ===========================================================================

#ifndef IPBR_GLOBALS_INCLUDED
#define IPBR_GLOBALS_INCLUDED

#ifdef IPBR

// ---------------------------------------------------------------------------
//  Uniforms Bliss does not already declare
// ---------------------------------------------------------------------------
uniform vec3 sunPosition;                   // view space, points at the sun/moon
uniform ivec2 eyeBrightnessSmooth;
uniform ivec2 atlasSize;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;

uniform int entityId;
uniform int blockEntityId;
uniform int heldItemId;
uniform int heldItemId2;
uniform int currentRenderedItemId;
uniform int isEyeInWater;

// ---------------------------------------------------------------------------
//  Material state -- written by the transplanted tables,
//  consumed by the G-buffer write in all_solid.fsh
// ---------------------------------------------------------------------------
int mat;
int subsurfaceMode;
bool noSmoothLighting, noDirectionalShading, noVanillaAO;
bool centerShadowBias, noGeneratedNormals, doTileRandomisation;
float smoothnessG, smoothnessD, highlightMult;
float emission, materialMask, noiseFactor, snowFactor;
float snowMinNdotU, noPuddles;
vec3 maRecolor;

// ---------------------------------------------------------------------------
//  Sample-level environment
// ---------------------------------------------------------------------------
vec4 glColorRaw;        // vertex colour exactly as the vertex stage saw it
vec4 glColor;           // vertex colour as the tables expect it
vec4 color;             // texture colour * vertex colour
vec3 colorP;            // texture colour before the vertex colour multiply

// Complementary declares in vec2 texCoord as a file-scope varying.  Keeping it
// a plain global assigned in main() makes fwidth(texCoord) collapse to 0 on some
// drivers, which silently kills generated normals (the offset falls back to
// nothing and GetDif returns 0 everywhere).  Aliasing the varying directly keeps
// the derivative real.  In IPBR mode adjustedTexCoord == lmtexcoord.xy anyway.
#define texCoord lmtexcoord.xy

vec2 midCoord;
vec2 absMidCoordPos;
vec2 signMidCoordPos;

vec2 lmCoord;
vec2 lmCoordM;

vec3 viewPos;
vec3 nViewPos;
float lViewPos;
vec3 playerPos;

vec3 normalM;

// le perfecto bliss: written from INSIDE GenerateNormals so the debug view reports
// what the real function computed, rather than what a replica of it computes.
//   x = lOriginalAlbedo   y = normalMap.x   z = normalMap.y   w = 1 if it ran
vec4 ipbrGNDebug = vec4(0.0);
vec2 ipbrTexCoordFwidth = vec2(0.0);

// le perfecto bliss: state of the final normal safety net.
//   x = 1 if it replaced normalM   y = |normalM|^2 before   z = |normalM|^2 after
vec3 ipbrNormalDebug = vec3(0.0);
vec3 geoNormal;
vec3 worldGeoNormal;
vec3 shadowMult;

// Texture-space tangent basis and mip level.  Complementary declares these at
// file scope too, because GenerateNormals / CoatTextures read them as globals.
// le perfecto bliss: named ipbrTbnMatrix, NOT tbnMatrix.  all_solid.fsh declares
// its own mat3 tbnMatrix as a local inside main() at line 363, so an assignment
// to 	bnMatrix from within main() (ipbr_solid.glsl) silently wrote to Bliss'
// local, while GenerateNormals -- a function at file scope -- read this global,
// which was never assigned.  A zero matrix makes normalize(normalMap * m)
// return NaN, which the normal safety net then replaces with the geometric
// normal on every fragment: generated normals rendered as if disabled.
mat3 ipbrTbnMatrix;

// le perfecto bliss: the atlas size actually resolved at runtime, for the debug view.
vec2 ipbrAtlasSizeDebug = vec2(0.0);
vec2 midCoordPos;
vec2 atlasSizeM;
float miplevel;

vec3 upVec, eastVec, northVec;
vec3 sunVec;
vec3 lightVec;
float NdotU, geoNdotU, NdotUmax0, SdotU;
float sunFactor, sunVisibility, sunVisibility2;
float shadowTime, shadowTimeVar1, shadowTimeVar2;
float noonFactor, noonFactorRaw, invNoonFactor;
float nightFactor, invNightFactor;
float rainFactor, rainFactor2, invRainFactor;
float inRainy, inSnowy;
float eyeBrightnessM, eyeBrightnessM2;
float dither;

#endif // IPBR
#endif // IPBR_GLOBALS_INCLUDED
