// Reduced-resolution reflection prepass (compute, world0/composite2_a/_b/_c/_d.csh).
// Compiled from dimensions/composite1.fsh with REFL_PREPASS = 1 (blocks), 2 (water/glass),
// 3 (horizontal blur of 1) or 4 (vertical blur of 3). Each invocation handles one low-res texel at the full-res
// pixel it stands for; the lighting pass upsamples the result.
//
// Iris requires the letters to be contiguous from _a: it collects <program>_a.csh, _b.csh, _c.csh ... and stops at
// the first missing one. A gap silently drops every later pass.

layout(local_size_x = 8, local_size_y = 8) in;

// Read by composite1.vsh, not by the lighting pass itself.
uniform float sunElevation;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int framemod8;
#include "/lib/TAA_jitter.glsl"

#if REFL_PREPASS == 2
	#define REFL_RES REFLECTION_RES_MIRROR
#else
	#define REFL_RES REFLECTION_RES_WORLD
#endif
#if (REFL_PREPASS == 1 && !defined REFL_PREPASS_WORLD) || (REFL_PREPASS == 2 && !defined REFL_PREPASS_MIRROR) || ((REFL_PREPASS == 3 || REFL_PREPASS == 4) && !defined REFL_BLUR_AVAILABLE)
	// The pass is not needed at all (blur off, or no prepass in this dimension): dispatch one group and return.
	const vec2 workGroupsRender = vec2(0.015625, 0.015625);
#elif REFL_PREPASS == 3 || REFL_PREPASS == 4
	// The blur runs on its own fixed fraction of the screen, not at the trace's resolution.
	const vec2 workGroupsRender = vec2(REFL_BLUR_SCALE, REFL_BLUR_SCALE);
#elif REFL_RES == 25
	const vec2 workGroupsRender = vec2(0.25, 0.25);
#elif REFL_RES == 50
	const vec2 workGroupsRender = vec2(0.5, 0.5);
#elif REFL_RES == 75
	const vec2 workGroupsRender = vec2(0.75, 0.75);
#else
	const vec2 workGroupsRender = vec2(1.0, 1.0);
#endif

void main() {
#if (REFL_PREPASS == 1 && defined REFL_PREPASS_WORLD) || (REFL_PREPASS == 2 && defined REFL_PREPASS_MIRROR)
	float scale = float(REFL_RES) * 0.01;
	vec2 screen = vec2(viewWidth, viewHeight);
	ivec2 lo = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(lo, ivec2(ceil(screen * scale))))) return;
	ivec2 px = min(ivec2((vec2(lo) + 0.5) / scale), ivec2(screen) - 1);
	prepassFragCoord = vec4(vec2(px) + 0.5, 0.5, 1.0);
	vec2 texcoord = prepassFragCoord.xy * texelSize;

	// What composite1.vsh passes the lighting pass.
	lightCol.rgb = texelFetch2D(colortex4, ivec2(6, 37), 0).rgb;
	lightCol.a = float(sunElevation > 1e-5) * 2.0 - 1.0;
	averageSkyCol_Clouds = texelFetch2D(colortex4, ivec2(0, 37), 0).rgb;
	unsigned_WsunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);
	vec3 moonVec = normalize(mat3(gbufferModelViewInverse) * moonPosition);
	WmoonVec = dot(-moonVec, unsigned_WsunVec) < 0.9999 ? -moonVec : moonVec;
	WsunVec = mix(WmoonVec, unsigned_WsunVec, clamp(lightCol.a, 0.0, 1.0));
	zMults = vec3(1.0 / (far * near), far + near, far - near);
	#ifdef TAA
		TAA_Offset = offsets[framemod8];
	#else
		TAA_Offset = vec2(0.0);
	#endif

	vec3 directLightColor = lightCol.rgb / 2400.0;
	vec3 ambientLightColor = averageSkyCol_Clouds / 900.0;
	#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
		directLightColor = luma(directLightColor) * vec3(DIRECTLIGHT_DIFFUSE_R, DIRECTLIGHT_DIFFUSE_G, DIRECTLIGHT_DIFFUSE_B);
		ambientLightColor = luma(ambientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R, INDIRECTLIGHT_DIFFUSE_G, INDIRECTLIGHT_DIFFUSE_B);
	#endif
	wsrSunDir = WsunVec;
	wsrDayFactor = clamp((unsigned_WsunVec.y + 0.05) / 0.15, 0.0, 1.0);

	// Per-frame dithering here flickers: the trace must be identical frame to frame for a still camera.
	// Blue noise per low-res texel gives the spatial spread, and TAA's sub-pixel jitter (TAA_Offset) is the
	// frame-to-frame variation the accumulation averages into a supersampled trace.
	vec2 BN = fract(R2_samples(0).xy + blueNoise(vec2(lo)).rg);
	float noiseZ = texelFetch2D(noisetex, lo % 512, 0).a;

	float z0 = texelFetch2D(depthtex0, px, 0).x;
	vec4 result = vec4(0.0, 0.0, 0.0, -1.0);

	#if REFL_PREPASS == 1
		float z = texelFetch2D(depthtex1, px, 0).x;
		if (z < 1.0) {
			vec4 data = texelFetch2D(colortex1, px, 0);
			vec4 dataUnpacked0 = vec4(decodeVec2(data.x), decodeVec2(data.y));
			vec4 dataUnpacked1 = vec4(decodeVec2(data.z), decodeVec2(data.w));
			vec3 normal = decode(dataUnpacked0.yw);
			vec2 lightmap = min(max(dataUnpacked1.yz - 0.05, 0.0) * 1.06, 1.0);
			vec4 SpecularTex = texelFetch2D(colortex8, px, 0);
			vec3 FlatNormals = normalize(texelFetch2D(colortex15, px, 0).rgb * 2.0 - 1.0);
			bool hand = abs(dataUnpacked1.w - 0.75) < 0.01;
			if (hand) {
				convertHandDepth(z);
				convertHandDepth(z0);
			}

			vec3 viewPos = toScreenSpace(vec3(texcoord / RENDER_SCALE - TAA_Offset * texelSize * 0.5, z));
			vec3 feetPlayerPos_normalized = normalize(mat3(gbufferModelViewInverse) * viewPos);
			vec3 specularNormal = dot(FlatNormals, feetPlayerPos_normalized) > 0.0 ? FlatNormals : normal;

			wsrLodScale = float(REFLECTION_RES_WORLD) * 0.01;
			wsrSunColor = directLightColor;
			wsrAmbientColor = ambientLightColor;
			specBehindTranslucent = z0 < z && !hand && texelFetch2D(colortex2, px, 0).a > 0.0;

			specularReflections(viewPos, feetPlayerPos_normalized, WsunVec, vec3(BN.xy, noiseZ), specularNormal,
				SpecularTex.r, SpecularTex.g, vec3(0.0), vec3(0.0), vec3(0.0), lightmap.y, hand, vec4(0.0));
			result = reflPrepassOut;
		}
		imageStore(reflWorld_img, lo, result);
		#ifdef REFL_BLUR_AVAILABLE
			// The blur passes overwrite this. Writing it here means that if they are ever skipped (a gap in the
			// _a/_b/_c/_d chain stops Iris collecting them) the lighting pass still finds the traced reflection
			// rather than an uninitialised image, and only loses the softness. The blur grid is coarser than the
			// trace, so this is a decimated copy.
			imageStore(reflWorldBlur_img, ivec2(vec2(lo) * (REFL_BLUR_SCALE / scale)), result);
		#endif
	#else
		uvec4 td = imageLoad(wsrTrans_img, px);
		if (z0 < 1.0 && td.w != 0u && abs(uintBitsToFloat(td.w) - z0) < 1e-6) {
			bool noWSR = unpackHalf2x16(td.y).y < 0.0;
			vec3 rayDir = WsrOctDecode(unpackSnorm2x16(td.z));
			vec3 viewPosS = toScreenSpace(vec3(texcoord / RENDER_SCALE - TAA_Offset * texelSize * 0.5, z0));
			vec3 surfPos = mat3(gbufferModelViewInverse) * viewPosS + gbufferModelViewInverse[3].xyz;
			vec3 viewDir = normalize(surfPos - gbufferModelViewInverse[3].xyz);
			vec3 surfNormal = normalize(rayDir - viewDir);

			wsrLodScale = float(REFLECTION_RES_MIRROR) * 0.01;
			wsrSunColor = lightCol.rgb / 2400.0;
			wsrAmbientColor = averageSkyCol_Clouds / 900.0;
			result = MirrorEnvironment(viewPosS, surfPos, surfNormal, rayDir, noWSR, BN.y, float(FORWARD_SSR_QUALITY));
			result.a = max(result.a, 0.0);
		}
		imageStore(reflMirror_img, lo, result);
	#endif
#endif
#if (REFL_PREPASS == 3 || REFL_PREPASS == 4) && defined REFL_BLUR_AVAILABLE
	// The roughness blur: the surface's cone spreads its reflection, and this is where those samples come from. It
	// runs on a FIXED fraction of the screen (REFL_BLUR_SCALE) rather than the trace's resolution, because that
	// coarse, mosaic-like grid is what gives a rough reflection its character -- at the trace's resolution a 50%-plus
	// trace is sharp enough that the same blur just looks like a soft mirror. The trace may be finer than this grid;
	// each coarse texel then reads the trace texel under it, so the cost does not grow with the resolution setting.
	// Taps step one coarse texel at a time (dense, so the average cannot sparkle), the kernel carries a tight core
	// plus a broad wash, and taps whose depth is not this surface are dropped, which keeps the blur on the
	// reflecting plane and stops it dragging a reflection across a silhouette.
	vec2 screen = vec2(viewWidth, viewHeight);
	float scale = float(REFL_RES) * 0.01;
	ivec2 lc = ivec2(gl_GlobalInvocationID.xy);
	ivec2 lcMax = ivec2(ceil(screen * REFL_BLUR_SCALE)) - 1;
	ivec2 traceMax = ivec2(ceil(screen * scale)) - 1;
	if (any(greaterThan(lc, lcMax))) return;

	// Width in coarse texels, capped so the two passes stay bounded: this is the only place the blur is paid for.
	int w = clamp(int(round(REFL_BLUR_PX * REFL_BLUR_SCALE)), 1, 16);
	// Trace texels per coarse texel (1, 2, 3 or 4 depending on the resolution setting).
	vec2 s = vec2(scale / REFL_BLUR_SCALE);
	ivec2 thisTrace = clamp(ivec2(vec2(lc) * s), ivec2(0), traceMax);
	ivec2 thisPx = min(ivec2((vec2(thisTrace) + 0.5) / scale), ivec2(screen) - 1);
	float refL = ld(texelFetch2D(depthtex1, thisPx, 0).x);

	vec4 sum = vec4(0.0);
	float weightSum = 0.0;
	for (int i = -16; i <= 16; i++) {
		if (i < -w || i > w) continue;
		#if REFL_PREPASS == 3
			ivec2 cc = lc + ivec2(i, 0);
		#else
			ivec2 cc = lc + ivec2(0, i);
		#endif
		cc = clamp(cc, ivec2(0), lcMax);
		vec4 v;
		#if REFL_PREPASS == 3
			// The trace holds the finer image: read the texel this coarse tap stands for.
			ivec2 tc = clamp(ivec2(vec2(cc) * s), ivec2(0), traceMax);
			v = imageLoad(reflWorld_img, tc);
		#else
			// The vertical pass reads the horizontal pass' result, which is already on the coarse grid.
			ivec2 tc = cc;
			v = imageLoad(reflWorldBlurTmp_img, cc);
		#endif
		ivec2 rep = min(ivec2((vec2(tc) + 0.5) / scale), ivec2(screen) - 1);
		if (abs(ld(texelFetch2D(depthtex1, rep, 0).x) - refL) > refL * 0.05 + 1e-4) continue;
		if (v.a < 0.0) continue;
		// Two scales in one kernel. A rough surface does not see a smeared copy of one object: it sees a tight core
		// around the mirror direction plus a broad wash of everything else the cone covers, and the wash is what
		// makes it read as rough. A single gaussian only ever gives the first of those.
		float t = float(i) / float(w);
		float weight = 0.55 * exp(-9.0 * t * t) + 0.45 * exp(-2.0 * t * t);
		sum += v * weight;
		weightSum += weight;
	}
	// With no usable tap the source's own value is kept: the blur can only ever soften a reflection, never drop it.
	#if REFL_PREPASS == 3
		vec4 fallback = imageLoad(reflWorld_img, thisTrace);
		imageStore(reflWorldBlurTmp_img, lc, weightSum > 0.0 ? sum / weightSum : fallback);
	#else
		vec4 fallback = imageLoad(reflWorldBlurTmp_img, lc);
		imageStore(reflWorldBlur_img, lc, weightSum > 0.0 ? sum / weightSum : fallback);
	#endif
#endif
}
