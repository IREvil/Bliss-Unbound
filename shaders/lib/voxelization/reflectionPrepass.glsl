// Reduced-resolution reflection prepass (compute, world0/composite2_a.csh and _b.csh).
// Compiled from dimensions/composite1.fsh with REFL_PREPASS = 1 (opaque) or 2 (water/glass). Each invocation
// traces one low-res texel at the full-res pixel it stands for; the lighting pass upsamples the result.

layout(local_size_x = 8, local_size_y = 8) in;

// Read by composite1.vsh, not by the lighting pass itself.
uniform float sunElevation;
uniform vec3 sunPosition;
uniform vec3 moonPosition;

#if REFL_PREPASS == 1
	#define REFL_RES REFLECTION_RES_WORLD
#else
	#define REFL_RES REFLECTION_RES_MIRROR
#endif
#if REFL_RES == 25
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
	TAA_Offset = vec2(0.0);

	vec3 directLightColor = lightCol.rgb / 2400.0;
	vec3 ambientLightColor = averageSkyCol_Clouds / 900.0;
	#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
		directLightColor = luma(directLightColor) * vec3(DIRECTLIGHT_DIFFUSE_R, DIRECTLIGHT_DIFFUSE_G, DIRECTLIGHT_DIFFUSE_B);
		ambientLightColor = luma(ambientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R, INDIRECTLIGHT_DIFFUSE_G, INDIRECTLIGHT_DIFFUSE_B);
	#endif
	wsrSunDir = WsunVec;
	wsrDayFactor = clamp((unsigned_WsunVec.y + 0.05) / 0.15, 0.0, 1.0);

	#ifdef TAA
		int seed = (frameCounter * 5) % 40000;
	#else
		int seed = 600;
	#endif
	vec2 BN = fract(R2_samples(seed).xy + blueNoise(prepassFragCoord.xy).rg);

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

			wsrSunColor = directLightColor;
			wsrAmbientColor = ambientLightColor;
			specBehindTranslucent = z0 < z && !hand && texelFetch2D(colortex2, px, 0).a > 0.0;

			specularReflections(viewPos, feetPlayerPos_normalized, WsunVec, vec3(BN.xy, blueNoise()), specularNormal,
				SpecularTex.r, SpecularTex.g, vec3(0.0), vec3(0.0), vec3(0.0), lightmap.y, hand, vec4(0.0));
			result = reflPrepassOut;
		}
		imageStore(reflWorld_img, lo, result);
	#else
		uvec4 td = imageLoad(wsrTrans_img, px);
		if (z0 < 1.0 && td.w != 0u && abs(uintBitsToFloat(td.w) - z0) < 1e-6) {
			bool noWSR = unpackHalf2x16(td.y).y < 0.0;
			vec3 rayDir = WsrOctDecode(unpackSnorm2x16(td.z));
			vec3 viewPosS = toScreenSpace(vec3(texcoord / RENDER_SCALE - TAA_Offset * texelSize * 0.5, z0));
			vec3 surfPos = mat3(gbufferModelViewInverse) * viewPosS + gbufferModelViewInverse[3].xyz;
			vec3 viewDir = normalize(surfPos - gbufferModelViewInverse[3].xyz);
			vec3 surfNormal = normalize(rayDir - viewDir);

			wsrSunColor = lightCol.rgb / 2400.0;
			wsrAmbientColor = averageSkyCol_Clouds / 900.0;
			result = MirrorEnvironment(viewPosS, surfPos, surfNormal, rayDir, noWSR, BN.y);
			result.a = max(result.a, 0.0);
		}
		imageStore(reflMirror_img, lo, result);
	#endif
#endif
}
