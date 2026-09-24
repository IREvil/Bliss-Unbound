// ===========================================================================
//  IntegratedPBR+ maths / colour helpers (no shader environment required)
//
//  Split out of ipbr_compat.glsl so the translucent material path can use them
//  without pulling in the helper functions that read the IPBR globals.
//
//  Copied from Complementary Unbound r5.9.1's lib/util/commonFunctions.glsl and
//  lib/util/dither.glsl (thanks to Jessie for the Bayer dithering).
//  See CREDITS.txt.
// ===========================================================================

#ifndef IPBR_MATH_INCLUDED
#define IPBR_MATH_INCLUDED

// ---------------------------------------------------------------------------
//  Constants
// ---------------------------------------------------------------------------
const float OSIEBCA = 1.0 / 255.0;          // One Step In Eight Bit Color Attachment
#ifndef GLASS_OPACITY
    #define GLASS_OPACITY 0.25
#endif
const float goldenRatio = 1.61803398875;

// ---------------------------------------------------------------------------
//  Small maths helpers (Complementary's commonFunctions.glsl)
//  `#ifndef` guards let Bliss' own macros win where it already defines one.
// ---------------------------------------------------------------------------
#ifndef max0
    int max0(int x) { return max(x, 0); }
    float max0(float x) { return max(x, 0.0); }
#endif
#ifndef clamp01
    int clamp01(int x) { return clamp(x, 0, 1); }
    float clamp01(float x) { return clamp(x, 0.0, 1.0); }
    vec2 clamp01(vec2 x) { return clamp(x, vec2(0.0), vec2(1.0)); }
    vec3 clamp01(vec3 x) { return clamp(x, vec3(0.0), vec3(1.0)); }
    vec4 clamp01(vec4 x) { return clamp(x, vec4(0.0), vec4(1.0)); }
#endif
#ifndef min1
    int min1(int x) { return min(x, 1); }
    float min1(float x) { return min(x, 1.0); }
    vec2 min1(vec2 x) { return min(x, vec2(1.0)); }
    vec3 min1(vec3 x) { return min(x, vec3(1.0)); }
    vec4 min1(vec4 x) { return min(x, vec4(1.0)); }
#endif

int pow2(int x) { return x * x; }
float pow2(float x) { return x * x; }
vec2 pow2(vec2 x) { return x * x; }
vec3 pow2(vec3 x) { return x * x; }
vec4 pow2(vec4 x) { return x * x; }

int pow3(int x) { return pow2(x) * x; }
float pow3(float x) { return pow2(x) * x; }
vec2 pow3(vec2 x) { return pow2(x) * x; }
vec3 pow3(vec3 x) { return pow2(x) * x; }
vec4 pow3(vec4 x) { return pow2(x) * x; }

// Fast approximations valid for x in [0, 1]
float pow1_5(float x) { return x - x * pow2(1.0 - x); }
vec2 pow1_5(vec2 x) { return x - x * pow2(1.0 - x); }
vec3 pow1_5(vec3 x) { return x - x * pow2(1.0 - x); }
vec4 pow1_5(vec4 x) { return x - x * pow2(1.0 - x); }

float sqrt1(float x) { return x * (2.0 - x); }
vec2 sqrt1(vec2 x) { return x * (2.0 - x); }
vec3 sqrt1(vec3 x) { return x * (2.0 - x); }
vec4 sqrt1(vec4 x) { return x * (2.0 - x); }

float sqrt2(float x) { x = 1.0 - x; x *= x; x *= x; return 1.0 - x; }
vec2 sqrt2(vec2 x) { x = 1.0 - x; x *= x; x *= x; return 1.0 - x; }
vec3 sqrt2(vec3 x) { x = 1.0 - x; x *= x; x *= x; return 1.0 - x; }
vec4 sqrt2(vec4 x) { x = 1.0 - x; x *= x; x *= x; return 1.0 - x; }

float sqrt3(float x) { x = 1.0 - x; x *= x; x *= x; x *= x; return 1.0 - x; }
vec2 sqrt3(vec2 x) { x = 1.0 - x; x *= x; x *= x; x *= x; return 1.0 - x; }
vec3 sqrt3(vec3 x) { x = 1.0 - x; x *= x; x *= x; x *= x; return 1.0 - x; }
vec4 sqrt3(vec4 x) { x = 1.0 - x; x *= x; x *= x; x *= x; return 1.0 - x; }

float sqrt4(float x) { x = 1.0 - x; x *= x; x *= x; x *= x; x *= x; return 1.0 - x; }
vec2 sqrt4(vec2 x) { x = 1.0 - x; x *= x; x *= x; x *= x; x *= x; return 1.0 - x; }
vec3 sqrt4(vec3 x) { x = 1.0 - x; x *= x; x *= x; x *= x; x *= x; return 1.0 - x; }
vec4 sqrt4(vec4 x) { x = 1.0 - x; x *= x; x *= x; x *= x; x *= x; return 1.0 - x; }

float smoothstep1(float x) { return x * x * (3.0 - 2.0 * x); }
vec2 smoothstep1(vec2 x) { return x * x * (3.0 - 2.0 * x); }
vec3 smoothstep1(vec3 x) { return x * x * (3.0 - 2.0 * x); }
vec4 smoothstep1(vec4 x) { return x * x * (3.0 - 2.0 * x); }

float dot3(vec3 x) { return dot(x, x); }
float minOf(vec3 x) { return min(x.x, min(x.y, x.z)); }
int minOf(ivec3 x) { return min(x.x, min(x.y, x.z)); }
float maxOf(vec3 x) { return max(x.x, max(x.y, x.z)); }
int maxOf(ivec3 x) { return max(x.x, max(x.y, x.z)); }

float GetLuminance(vec3 color) { return dot(color, vec3(0.299, 0.587, 0.114)); }
vec3 DoLuminanceCorrection(vec3 color) { return color / (GetLuminance(color) + 0.0001); }
vec3 DoReducedLuminanceCorrection(vec3 color, float reduceAmount) {
    return color / mix(GetLuminance(color), 1.0, reduceAmount);
}

float GetBiasFactor(float NdotLM) {
    float NdotLM2 = NdotLM * NdotLM;
    return 1.25 * (1.0 - NdotLM2 * NdotLM2) / NdotLM;
}

// ---------------------------------------------------------------------------
//  Colour probes -- these are what makes IntegratedPBR+ able to classify
//  vanilla textures without a resource pack.
// ---------------------------------------------------------------------------
bool CheckForColor(vec3 albedo, vec3 check) { // Thanks to Builderb0y
    vec3 dif = albedo - check * 0.003921568;
    return dot(dif, dif) < 0.00001;
}

bool CheckForStick(vec3 albedo) {
    return CheckForColor(albedo, vec3(40, 30, 11)) ||
            CheckForColor(albedo, vec3(73, 54, 21)) ||
            CheckForColor(albedo, vec3(104, 78, 30)) ||
            CheckForColor(albedo, vec3(137, 103, 39));
}

float GetMaxColorDif(vec3 color) {
    vec3 dif = abs(vec3(color.r - color.g, color.g - color.b, color.r - color.b));
    return max(dif.r, max(dif.g, dif.b));
}

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// ---------------------------------------------------------------------------
//  Dithering (Complementary lib/util/dither.glsl, thanks to Jessie)
// ---------------------------------------------------------------------------
#ifndef INCLUDE_DITHER
    #define INCLUDE_DITHER
    float Bayer2  (vec2 c) { c = 0.5 * floor(c); return fract(1.5 * fract(c.y) + c.x); }
    float Bayer4  (vec2 c) { return 0.25 * Bayer2  (0.5 * c) + Bayer2(c); }
    float Bayer8  (vec2 c) { return 0.25 * Bayer4  (0.5 * c) + Bayer2(c); }
    float Bayer16 (vec2 c) { return 0.25 * Bayer8  (0.5 * c) + Bayer2(c); }
    float Bayer32 (vec2 c) { return 0.25 * Bayer16 (0.5 * c) + Bayer2(c); }
    float Bayer64 (vec2 c) { return 0.25 * Bayer32 (0.5 * c) + Bayer2(c); }
    float Bayer128(vec2 c) { return 0.25 * Bayer64 (0.5 * c) + Bayer2(c); }
    float Bayer256(vec2 c) { return 0.25 * Bayer128(0.5 * c) + Bayer2(c); }
#endif



// ---------------------------------------------------------------------------
//  Translucent glass distance tweaks (Complementary materialMethods).
//  Environment-free, so it can live here and be shared by the solid and
//  translucent paths.
// ---------------------------------------------------------------------------
#ifndef IPBR_TRANSLUCENT_TWEAKS_INCLUDED
#define IPBR_TRANSLUCENT_TWEAKS_INCLUDED
#include "/lib/materials/materialMethods/translucentTweaks.glsl"
#endif

#endif // IPBR_MATH_INCLUDED
