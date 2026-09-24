float invLinZ (float lindepth){
	return -((2.0*near/lindepth)-far-near)/(far-near);
}
float linZ(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
	// l = (2*n)/(f+n-d(f-n))
	// f+n-d(f-n) = 2n/l
	// -d(f-n) = ((2n/l)-f-n)
	// d = -((2n/l)-f-n)/(f-n)

}

void frisvad(in vec3 n, out vec3 f, out vec3 r){
    if(n.z < -0.9) {
        f = vec3(0.,-1,0);
        r = vec3(-1, 0, 0);
    } else {
    	float a = 1./(1.+n.z);
    	float b = -n.x*n.y*a;
    	f = vec3(1. - n.x*n.x*a, b, -n.x) ;
    	r = vec3(b, 1. - n.y*n.y*a , -n.y);
    }
}

mat3 CoordBase(vec3 n){
	vec3 x,y;
    frisvad(n,x,y);
    return mat3(x,y,n);
}

vec2 R2_Sample(int n){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha * n);
}

float fma(float a,float b,float c){
 return a * b + c;
}

vec3 SampleVNDFGGX(
    vec3 viewerDirection, // Direction pointing towards the viewer, oriented such that +Z corresponds to the surface normal
    float alpha, // Roughness parameter along X and Y of the distribution
    vec2 xy // Pair of uniformly distributed numbers in [0, 1)
) {

    // Transform viewer direction to the hemisphere configuration
    viewerDirection = normalize(vec3( alpha * 0.5 * viewerDirection.xy, viewerDirection.z));

    // Sample a reflection direction off the hemisphere
    const float tau = 6.2831853; // 2 * pi
    float phi = tau * xy.x;

    float cosTheta = fma(1.0 - xy.y, 1.0 + viewerDirection.z, -viewerDirection.z);
    float sinTheta = sqrt(clamp(1.0 - cosTheta * cosTheta, 0.0, 1.0));

	sinTheta = clamp(sinTheta,0.0,1.0);
	cosTheta = clamp(cosTheta,sinTheta*0.5,1.0);

	
	vec3 reflected = vec3(vec2(cos(phi), sin(phi)) * sinTheta, cosTheta);

    // Evaluate halfway direction
    // This gives the normal on the hemisphere
    vec3 halfway = reflected + viewerDirection;

    // Transform the halfway direction back to hemiellispoid configuation
    // This gives the final sampled normal
    return normalize(vec3(alpha * halfway.xy, halfway.z));
}

vec3 GGX(vec3 n, vec3 v, vec3 l, float r, vec3 f0, vec3 metalAlbedoTint) {
  r = max(pow(r,2.5), 0.0001);

  vec3 h = normalize(l + v);
  float hn = inversesqrt(dot(h, h));

  float dotLH = clamp(dot(h,l)*hn,0.,1.);
  float dotNH = clamp(dot(h,n)*hn,0.,1.) ;
  float dotNL = clamp(dot(n,l),0.,1.);
  float dotNHsq = dotNH*dotNH;

  float denom = dotNHsq * r - dotNHsq + 1.;
  float D = r / (3.141592653589793 * denom * denom);

  vec3 F = (f0 + (1. - f0) * exp2((-5.55473*dotLH-6.98316)*dotLH)) * metalAlbedoTint;
  float k2 = .25 * r;

  return dotNL * D * F / (dotLH*dotLH*(1.0-k2)+k2);
}

// Complementary's sun highlight (lib/lighting/ggx.glsl): fixed 0.05 F0, roughness floor, soft-capped at 8.
// viewDir points from the camera to the surface.
float IpbrHighlight(vec3 n, vec3 viewDir, vec3 l, float smoothnessG) {
	float NdotL = clamp(dot(n, l), 0.0, 1.0);
	if (NdotL <= 0.0) return 0.0;

	float s = smoothnessG * 0.9 + 0.1;
	s = s * (2.0 - s);
	float r = 1.35 - s;
	r *= r; r *= r;

	vec3 h = normalize(l - viewDir);
	float dotLH = clamp(dot(h, l), 0.0, 1.0);
	float dotNH = clamp(dot(n, h), 0.0, 1.0);
	dotNH *= dotNH;

	float denom = dotNH * r - dotNH + 1.0;
	float D = r / (3.141592653589793 * denom * denom);
	float F = exp2((-5.55473 * dotLH - 6.98316) * dotLH) * 0.95 + 0.05;

	float NdotLM = 1.0 - NdotL * NdotL;
	NdotLM *= NdotLM; NdotLM *= NdotLM; NdotLM *= NdotLM;
	NdotLM = 1.0 - NdotLM;

	float spec = max(NdotLM * D * F / max(dotLH * dotLH, 1e-4), 0.0);
	return spec / (0.125 * spec + 1.0);
}

float shlickFresnelRoughness(float XdotN, float roughness){

	float shlickFresnel = clamp(1.0 + XdotN,0.0,1.0);

	float curves = exp(-4.0*pow(1.0-(roughness),2.5));
	float brightness = exp(-3.0*pow(1.0-sqrt(roughness),3.50));

	shlickFresnel = pow(1.0-pow(1.0-shlickFresnel, mix(1.0, 1.9, curves)),mix(5.0, 2.6, curves));
	shlickFresnel = mix(0.0, mix(1.0,0.065,  brightness) , clamp(shlickFresnel,0.0,1.0));
	
	return shlickFresnel;
}

vec3 rayTraceSpeculars(vec3 dir, vec3 position, float dither, float quality, bool hand, inout float reflectionLength){

	float biasAmount = 0.000075;

	vec3 clipPosition = toClipSpace3(position);
	float rayLength = ((position.z + dir.z * far*sqrt(3.)) > -near) ? (-near -position.z) / dir.z : far*sqrt(3.);
	vec3 direction = toClipSpace3(position + dir*rayLength) - clipPosition;  //convert to clip space
	vec3 reflectedTC = vec3((direction.xy + clipPosition.xy) * RENDER_SCALE, 0.999999);

	#if FORWARD_SSR_QUALITY == 1
		return reflectedTC;
	#endif

	// The hand's march result is discarded below; only its step count feeds the blur.
	if(hand) { reflectionLength = 1.0; return reflectedTC; }
	#if DEFERRED_SSR_QUALITY != 1
		// Rays aimed back at the camera stay on screen and rarely hit anything, so they ran every step (dead-on views, water below).
		if(dir.z > 0.7) return vec3(1.1);
	#endif

	//get at which length the ray intersects with the edge of the screen
	vec3 maxLengths = (step(0.0, direction) - clipPosition) / direction;
	float mult = min(min(maxLengths.x, maxLengths.y), maxLengths.z);
	vec3 stepv = direction * mult / quality;

	clipPosition.xy *= RENDER_SCALE;
	stepv.xy *= RENDER_SCALE;

	vec3 spos = clipPosition + stepv*dither;
	spos += stepv*0.5 + vec3(0.5*texelSize,0.0); // small offsets to reduce artifacts from precision differences.
	
	#if defined DEFERRED_SPECULAR && defined TAA
		spos.xy += TAA_Offset*texelSize*0.5/RENDER_SCALE;
	#endif

	float minZ = spos.z - 0.00025 / linZ(spos.z);
	float maxZ = spos.z;
	
	vec3 hitPos = vec3(1.1);

  	for (int i = 0; i <= int(quality); i++) {
		#if DEFERRED_SSR_QUALITY != 1
			if(!hand && (spos.x < 0 || spos.x > 1 || spos.y < 0 || spos.y > 1)) return vec3(1.1);
		#endif

		float sampleDepth = sqrt(texelFetch2D(colortex4, ivec2(spos.xy/texelSize/4.0),0).a/65000.0);
		float sp = invLinZ(sampleDepth);

		if(sp < max(minZ, maxZ) && sp > min(minZ, maxZ)) {
			hitPos = vec3(spos.xy/RENDER_SCALE, sp);
			break;
		}
		
		minZ = maxZ - biasAmount / linZ(spos.z);
		maxZ += stepv.z;

		spos += stepv;

		reflectionLength += 1.0 / quality;
  	}


	#if DEFERRED_SSR_QUALITY == 1
		return reflectedTC;
	#endif

	if(hand) return reflectedTC;
	return hitPos;
}

// Set by screenSpaceReflections: distance to the hit along the ray, how far it sits off the ray, and its camera distance.
float ssrHitDist = -1.0;
float ssrHitError = 1e9;
float ssrHitCamDist = 0.0;

// Set by composite1 when a translucent (water, glass) covers the pixel: its own forward pass already traced a reflection there.
bool specBehindTranslucent = false;

#if defined WSR_DEFER_FORWARD || defined WSR_DEFER_RESOLVE
	// Forward pass -> lighting composite: the reflection colour a WSR hit replaces, its weight, and the ray.
	vec3 wsrDeferBase = vec3(0.0);
	float wsrDeferWeight = 0.0;
	vec3 wsrDeferDir = vec3(0.0, 1.0, 0.0);

	vec2 WsrOctEncode(vec3 n) {
		n /= abs(n.x) + abs(n.y) + abs(n.z);
		vec2 e = n.xz;
		if (n.y < 0.0) e = (1.0 - abs(e.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.z >= 0.0 ? 1.0 : -1.0);
		return e;
	}
	vec3 WsrOctDecode(vec2 e) {
		vec3 n = vec3(e.x, 1.0 - abs(e.x) - abs(e.y), e.y);
		if (n.y < 0.0) n.xz = (1.0 - abs(n.zx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.z >= 0.0 ? 1.0 : -1.0);
		return normalize(n);
	}
#endif

vec4 screenSpaceReflections(
	vec3 reflectedVector,
	vec3 viewPos,
	float noise,

	bool isHand,
	float roughness,
	inout float backgroundReflectMask
){
	vec4 reflection = vec4(0.0);
	float reflectionLength = 0.0;

	float quality = 1.0f;
	#if defined FORWARD_SPECULAR
		quality = float(FORWARD_SSR_QUALITY);
	#endif
	#if defined DEFERRED_SPECULAR
		quality = float(DEFERRED_SSR_QUALITY);
	#endif

	vec3 raytracePos = rayTraceSpeculars(reflectedVector, viewPos, noise, quality, isHand, reflectionLength);
	ssrHitDist = -1.0;
	ssrHitError = 1e9;
	if (raytracePos.z > 1.0) return reflection;

	if (raytracePos.z < 0.999999) {
		vec3 hitViewPos = toScreenSpace(raytracePos);
		vec3 hitOffset = hitViewPos - viewPos;
		ssrHitDist = dot(hitOffset, normalize(reflectedVector));
		ssrHitError = length(hitOffset - ssrHitDist * normalize(reflectedVector));
		ssrHitCamDist = length(hitViewPos);
	}

	// use higher LOD as the reflection goes on, to blur it. this helps denoise a little.
	reflectionLength = min(max(reflectionLength - 0.1, 0.0)/0.9, 1.0);
	float LOD = mix(0.0, 6.0*(1.0-exp(-15.0*sqrt(roughness))), 1.0-pow(1.0-reflectionLength,5.0));

	vec3 previousPosition = mat3(gbufferModelViewInverse) * toScreenSpace(raytracePos) + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition);
	previousPosition = mat3(gbufferPreviousModelView) * previousPosition + gbufferPreviousModelView[3].xyz;
	previousPosition.xy = projMAD(gbufferPreviousProjection, previousPosition).xy / -previousPosition.z * 0.5 + 0.5;

	if (previousPosition.x > 0.0 && previousPosition.y > 0.0 && previousPosition.x < 1.0 && previousPosition.y < 1.0) {
		
		if(raytracePos.z > 0.999999) backgroundReflectMask = 1.0;

		#if defined OVERWORLD_SHADER 
			reflection.a = raytracePos.z > 0.999999 ? (isHand || isEyeInWater == 1 ? 1.0 : 0.0) : 1.0;
		#else
			reflection.a = 1.0;
		#endif
		
		#ifdef FORWARD_RENDERED_SPECULAR
			// vec2 clampedRes = max(vec2(viewWidth,viewHeight),vec2(1920.0,1080.));
			// vec2 resScale = vec2(1920.,1080.)/clampedRes;
			// vec2 bloomTileUV = (((previousPosition.xy/texelSize)*2.0 + 0.5)*texelSize/2.0) / clampedRes*vec2(1920.,1080.);
			// reflection.rgb = texture2D(colortex6, bloomTileUV / 4.0).rgb;
			reflection.rgb = texture2D(colortex5, previousPosition.xy).rgb;
		#else
			reflection.rgb = texture2DLod(colortex5, previousPosition.xy, LOD).rgb;
		#endif
	}

	// reflection.rgb = vec3(LOD/6);

// vec2 clampedRes = max(vec2(viewWidth,viewHeight),vec2(1920.0,1080.));
// vec2 resScale = vec2(1920.,1080.)/clampedRes;
// vec2 bloomTileUV = (((previousPosition.xy/texelSize)*2.0 + 0.5)*texelSize/2.0) / clampedRes*vec2(1920.,1080.);

// vec2 bloomTileoffsetUV[6] = vec2[](
//  	bloomTileUV / 4.,
//  	bloomTileUV / 8.   + vec2(0.25*resScale.x+2.5*texelSize.x, 		.0),
//  	bloomTileUV / 16.  + vec2(0.375*resScale.x+4.5*texelSize.x, 	.0),
//  	bloomTileUV / 32.  + vec2(0.4375*resScale.x+6.5*texelSize.x, 	.0),
//  	bloomTileUV / 64.  + vec2(0.46875*resScale.x+8.5*texelSize.x,  	.0),
//  	bloomTileUV / 128. + vec2(0.484375*resScale.x+10.5*texelSize.x,	.0)
// );
// // reflectLength = pow(1-pow(1-reflectLength,2),5) * 6;
// reflectLength = (exp(-4*(1-reflectLength))) * 6;
// Reflections.rgb = texture2D(colortex6, bloomTileoffsetUV[0]).rgb;

	return reflection;
}

float getReflectionVisibility(float f0, float roughness){

	// the goal is to determine if the reflection is even visible. 
	// if it reaches a point in smoothness or reflectance where it is not visible, allow it to interpolate to diffuse lighting.
	float thresholdValue = ROUGHNESS_TRESHOLD;

	if(thresholdValue < 0.01) return 0.0;

	// the visibility gradient should only happen for dialectric materials. because metal is always shiny i guess or something
	float dialectrics = max(f0*255.0 - 26.0,0.0)/229.0;
	float value = 0.35; // so to a value you think is good enough.
	float thresholdA = min(max( (1.0-dialectrics) - value, 0.0)/value, 1.0);

	// use perceptual smoothness instead of linear roughness. it just works better i guess
	float smoothness = 1.0-sqrt(roughness);
	value = thresholdValue; // this one is typically want you want to scale.
	float thresholdB = min(max(smoothness - value, 0.0)/value, 1.0);
	
	// preserve super smooth reflections. if thresholdB's value is really high, then fully smooth, low f0 materials would be removed (like water).
	value = 0.1; // super low so only the smoothest of materials are includes.
	float thresholdC = 1.0-min(max(value - (1.0-smoothness), 0.0)/value, 1.0);
	
	float visibilityGradient = max(thresholdA*thresholdC - thresholdB,0.0);

	// a curve to make the gradient look smooth/nonlinear. just preference
	visibilityGradient = 1.0-visibilityGradient;
	visibilityGradient *=visibilityGradient;
	visibilityGradient = 1.0-visibilityGradient;
	visibilityGradient *=visibilityGradient;

	return visibilityGradient;
}

// derived from N and K from labPBR wiki https://shaderlabs.org/wiki/LabPBR_Material_Standard
// using ((1.0 - N)^2 + K^2) / ((1.0 + N)^2 + K^2)
vec3 HCM_F0 [8] = vec3[](
	vec3(0.531228825312, 0.51235724246, 0.495828545714),// iron	
	vec3(0.944229966045, 0.77610211732, 0.373402004593),// gold		
	vec3(0.912298031535, 0.91385063144, 0.919680580954),// Aluminum
	vec3(0.55559681715,  0.55453707574, 0.554779427513),// Chrome
	vec3(0.925952196272, 0.72090163805, 0.504154241735),// Copper
	vec3(0.632483812932, 0.62593707362, 0.641478899539),// Lead
	vec3(0.678849234658, 0.64240055565, 0.588409633571),// Platinum
	vec3(0.961999998804, 0.94946811207, 0.922115710997)	// Silver
);

vec3 specularReflections(

	in vec3 viewPos, // toScreenspace(vec3(screenUV, depth)
	in vec3 playerPos, // normalized
    in vec3 lightPos, // should be in world space
    in vec3 noise, // x = bluenoise y = interleaved gradient noise

	in vec3 normal, // normals in world space
	in float roughness, // red channel of specular texture _S
	in float f0, // green channel of specular texture _S
	in vec3 albedo, 
	in vec3 diffuseLighting, 
	in vec3 lightColor, // should contain the light's color and shadows.

    in float lightmap, // in anything other than world0, this should be 1.0;
    in bool isHand // mask for the hand

	#ifdef FORWARD_SPECULAR
	, bool isWater
	, inout float reflectanceForAlpha
	#endif
	
	,in vec4 flashLight_stuff

){
	#ifdef FORWARD_RENDERED_SPECULAR
		lightmap = pow(min(max(lightmap-0.6,0.0)*2.5,1.0),2.0);
	#else
		lightmap = clamp((lightmap-0.8)*7.0, 0.0,1.0);
	#endif

	roughness = 1.0 - roughness; 
	roughness *= roughness;

	float highlightRoughness = roughness;
	#if IPBR_MODE == 1 && defined DEFERRED_SPECULAR && !defined FORWARD_SPECULAR
		bool ipbrIntense = false;
		bool ipbrDielectric = f0 < 229.5/255.0;
		float ipbrSmoothnessG = 0.0;
		vec3 ipbrReflectColor = vec3(1.0);
		if (ipbrDielectric) {
			// all_solid.fsh packs dielectrics as 0.45 intense flag + 0.44 * smoothnessG.
			ipbrIntense = f0 > 0.445;
			ipbrSmoothnessG = clamp((f0 - (ipbrIntense ? 0.45 : 0.0)) / 0.44, 0.0, 1.0);
			highlightRoughness = (1.0 - ipbrSmoothnessG) * (1.0 - ipbrSmoothnessG);
			f0 = 0.04;
		} else {
			// Codes 234/231/230 are Comp's copper/gold/redstone fresnel: intense dielectrics with a tinted reflection
			// (deferredIPBR.glsl), not metals. As Bliss metals they lost their diffuse and went black at grazing angles.
			float ipbrS = 1.0 - sqrt(roughness);
			int ipbrCode = int(f0 * 255.0 + 0.5);
			if (ipbrCode == 234) ipbrReflectColor = mix(vec3(0.5, 0.75, 0.5), vec3(1.0, 0.45, 0.3), ipbrS * (2.0 - ipbrS));
			else if (ipbrCode == 231) ipbrReflectColor = vec3(1.0, 0.8, 0.5);
			else if (ipbrCode == 230) ipbrReflectColor = vec3(1.0, 0.3, 0.2);
			ipbrIntense = true;
			ipbrDielectric = true;
			ipbrSmoothnessG = ipbrS;
			f0 = 0.04;
		}
	#endif

	f0 = f0 == 0.0 ? 0.02 : f0;

	// f0 = 0.1;
	// roughness = 0.0;

	bool isMetal = f0 > 229.5/255.0;

	// get reflected vector
	mat3 basis = CoordBase(normal);
	vec3 viewDir = -playerPos*basis;

	#if defined FORWARD_ROUGH_REFLECTION || defined DEFERRED_ROUGH_REFLECTION
		#if IPBR_MODE == 1 && defined DEFERRED_SPECULAR && !defined FORWARD_SPECULAR
			// Upstream's bounded normal jitter (composite.glsl): GGX's long tail sends rays into bright HDR hits -> fireflies.
			vec3 roughJitter = vec3(noise.xy, fract(noise.x + noise.y * 0.618034)) - 0.5;
			vec3 reflectedVector_L = reflect(playerPos, normalize(normal + 0.3 * roughness * roughJitter));
			if (dot(reflectedVector_L, normal) < 0.0) reflectedVector_L = reflect(playerPos, normal);
		#else
			vec3 samplePoints = SampleVNDFGGX(viewDir, roughness, noise.xy);
			vec3 reflectedVector_L = basis * reflect(-normalize(viewDir), samplePoints);
		#endif

		reflectedVector_L = isHand ? reflect(playerPos, normal) : reflectedVector_L;
	#else
		vec3 reflectedVector_L = reflect(playerPos, normal);
	#endif
	float VdotN = dot(-normalize(viewDir), vec3(0.0,0.0,1.0));
	float shlickFresnel = shlickFresnelRoughness(VdotN, roughness);

	// F0 <  230 dialectrics
	// F0 >= 230 hardcoded metal f0
	// F0 == 255 use albedo for f0
	albedo = f0 == 1.0 ? sqrt(albedo) : albedo;
	vec3 metalAlbedoTint = isMetal ? albedo : vec3(1.0);
	// get F0 values for hardcoded metals.
	vec3 hardCodedMetalsF0 = f0 == 1.0 ? albedo : HCM_F0[int(clamp(f0*255.0 - 229.5,0.0,7.0))];
	vec3 reflectance = isMetal ? hardCodedMetalsF0 : vec3(f0);
	vec3 F0 = (reflectance + (1.0-reflectance) * shlickFresnel) * metalAlbedoTint;

	#if IPBR_MODE == 1 && defined DEFERRED_SPECULAR && !defined FORWARD_SPECULAR
		// Complementary's reflection weight (deferred1.glsl): fresnel * sqrt1(smoothnessD), sqrt1(x) = x * (2 - x).
		if (!isMetal) {
			float fresnelC = clamp(1.0 + VdotN, 0.0, 1.0) * 0.7 + 0.3;
			fresnelC = ipbrIntense ? fresnelC * 0.75 + 0.25 * IPBR_INTENSE_FRESNEL_MULT * 0.01 : fresnelC * fresnelC;
			float smoothnessD = max(1.0 - sqrt(roughness), 0.0);
			F0 = vec3(fresnelC * smoothnessD * (2.0 - smoothnessD) * IPBR_SPECULAR_STRENGTH * 0.01);
		}
	#endif

	#if defined FORWARD_SPECULAR
		reflectanceForAlpha = clamp(dot(F0, vec3(0.3333333)), 0.0,1.0);
		
		#if defined SNELLS_WINDOW
			if(isEyeInWater == 1 && isWater){
				// emulate how mojang did snells window in vibrant visuals because it works nicely tbh
				float snellsWindow = min(max(0.54 - clamp(1.0 + VdotN,0,1),0)/0.1,1);
				snellsWindow = 1.0-snellsWindow*snellsWindow;
				snellsWindow *= snellsWindow*snellsWindow;
				reflectanceForAlpha = f0 + (1.0-f0) * snellsWindow;
			}
		#endif
	#endif

	vec3 specularReflections = diffuseLighting;

	float reflectionVisibilty = getReflectionVisibility(f0, roughness);
	#if IPBR_MODE == 1 && defined DEFERRED_SPECULAR && !defined FORWARD_SPECULAR
		// Upstream reflects whenever the weight is non-zero, so gate on the weight rather than on smoothness.
		if (!isMetal) reflectionVisibilty = 1.0 - clamp(F0.x / max(IPBR_REFLECTION_THRESHOLD, 1e-4) - 1.0, 0.0, 1.0);
	#endif
	#if defined DEFERRED_BACKGROUND_REFLECTION || defined FORWARD_BACKGROUND_REFLECTION || DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0
		#if BLOCK_REFLECT_QUALITY == 0 && !defined FORWARD_SPECULAR
			bool specEnvironmentOff = true; // LOW: sun and moon highlight only
		#else
			bool specEnvironmentOff = specBehindTranslucent;
		#endif
		if(reflectionVisibilty < 1.0 && !specEnvironmentOff){
			
			float backgroundReflectMask = lightmap;

			#if defined DEFERRED_BACKGROUND_REFLECTION || defined FORWARD_BACKGROUND_REFLECTION
				#if !defined OVERWORLD_SHADER
					vec3 backgroundReflection = volumetricsFromTex(reflectedVector_L, colortex4, roughness).rgb / 1200.0;
				#else
					vec3 backgroundReflection = skyCloudsFromTex(reflectedVector_L, colortex4).rgb / 1200.0;
					#if defined SNELLS_WINDOW
						if(isEyeInWater == 1) backgroundReflection *= exp(-vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B) * 15.0)*2;
					#endif
				#endif
			#endif
			#if DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0
				// Opaque surfaces always go WSR-first like upstream; mirrors (forward: glass, water, ice) follow the mode.
				#ifdef FORWARD_SPECULAR
					bool mirrorSkyOnly = isWater ? WATER_REFLECT_QUALITY < 0 : GLASS_REFLECT_QUALITY < 0; // POTATO: sky only
				#else
					const bool mirrorSkyOnly = false;
				#endif
				#if defined FORWARD_SPECULAR && WATER_REFLECT_QUALITY < 0 && GLASS_REFLECT_QUALITY < 0
					vec4 enviornmentReflection = vec4(0.0);
				#elif defined INCLUDE_BLISS_WSR && (WORLD_SPACE_REF_MODE == 1 || !defined FORWARD_SPECULAR)
					vec4 enviornmentReflection = vec4(0.0);
					wsrHitDist = -2.0;
					if (!mirrorSkyOnly) {
					if (!isHand) {
						vec3 wsrPlayerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
						enviornmentReflection = BlissWSR(wsrPlayerPos, normal, normalize(reflectedVector_L));
					}
					bool wsrHit = enviornmentReflection.a > 0.0;
					bool wsrCovered = wsrHitDist > -1.5;

					float ssrMask = backgroundReflectMask;
					vec4 ssr = screenSpaceReflections(mat3(gbufferModelView) * reflectedVector_L, viewPos, noise.z, isHand, roughness, ssrMask);
					// Upstream's rule: inside the volume SSR only adds what voxels lack (entities, plants), i.e. a hit that
					// really lies on the ray and in front of the WSR hit, or anything past the volume.
					float fresnelSSR = clamp(1.0 + VdotN, 0.0, 1.0);
					bool ssrPlausible = ssrHitDist > 0.0 && ssrHitError * (1.0 - fresnelSSR) < 1.0 + ssrHitCamDist * 0.2;
					bool ssrOnRay = ssrPlausible && ssrHitError < 0.5 + 0.03 * ssrHitDist;
					bool ssrBeyond = ssrPlausible && ssrHitCamDist > 0.25 * float(COLORED_LIGHTING_INTERNAL);
					bool ssrUsable = ssr.a > 0.0 && (ssrOnRay || ssrBeyond) && (!wsrHit || ssrHitDist < wsrHitDist - 0.3);

					if (!wsrCovered) {
						enviornmentReflection = ssr;
						backgroundReflectMask = ssrMask;
					} else if (ssrUsable) {
						enviornmentReflection.rgb = mix(enviornmentReflection.rgb, ssr.rgb, ssr.a);
						enviornmentReflection.a = max(enviornmentReflection.a, ssr.a);
					}
					#if DEBUG_VIEW == debug_WSR
						if (!isHand) enviornmentReflection = vec4(wsrHit ? vec3(0.0, 10.0, 0.0) : ssrUsable ? vec3(0.0, 0.0, 10.0) : vec3(10.0, 0.0, 0.0), 1.0);
					#endif
					}
				#else
				vec4 enviornmentReflection = vec4(0.0);
				if (!mirrorSkyOnly) {
				enviornmentReflection = screenSpaceReflections(mat3(gbufferModelView) * reflectedVector_L, viewPos, noise.z, isHand, roughness, backgroundReflectMask);

				#if defined INCLUDE_BLISS_WSR
					if (enviornmentReflection.a < 0.999 && !isHand) {
						vec3 wsrPlayerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
						vec4 wsr = BlissWSR(wsrPlayerPos, normal, normalize(reflectedVector_L));
						enviornmentReflection.rgb = mix(wsr.rgb, enviornmentReflection.rgb, enviornmentReflection.a);
						enviornmentReflection.a = max(enviornmentReflection.a, wsr.a);
						#if DEBUG_VIEW == debug_WSR
							enviornmentReflection = vec4(wsr.a > 0.0 ? vec3(0.0, 10.0, 0.0) : vec3(10.0, 0.0, 0.0), 1.0);
						#endif
					}
				#endif
				#if defined INCLUDE_PLAYER_REF && defined WSR_DEFER_FORWARD && defined FORWARD_SPECULAR
					// SSR cannot see the first-person player; it wins over whatever SSR found behind it.
					if (!isHand) {
						vec3 prPlayerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + 0.04 * normal;
						float prLimit = enviornmentReflection.a > 0.0 && ssrHitDist > 0.0 ? ssrHitDist : 999999.0;
						vec4 playerRef = BlissPlayerRef(prPlayerPos, normalize(reflectedVector_L), prLimit, wsrSunColor, wsrAmbientColor, wsrSunDir);
						if (playerRef.a > 0.0) enviornmentReflection = playerRef;
					}
				#endif
				}
				#endif
				// darkening for metals.
				vec3 DarkenedDiffuseLighting = isMetal ? diffuseLighting * (1.0-enviornmentReflection.a) * (1.0-lightmap) : diffuseLighting;
			#else
				// darkening for metals.
				vec3 DarkenedDiffuseLighting = isMetal ? diffuseLighting * (1.0-lightmap) : diffuseLighting;
			#endif

			// composite all the different reflections together
			#if IPBR_MODE == 1 && defined DEFERRED_SPECULAR && !defined FORWARD_SPECULAR
				vec3 ipbrRefScale = ipbrReflectColor;
				#ifdef INCLUDE_BLISS_WSR
					ipbrRefScale *= mix(float(WSR_NIGHT_STRENGTH), float(WSR_DAY_STRENGTH), wsrDayFactor) * 0.01;
				#endif
				#if defined DEFERRED_BACKGROUND_REFLECTION || defined FORWARD_BACKGROUND_REFLECTION
					backgroundReflection *= ipbrRefScale;
				#endif
				#if DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0
					enviornmentReflection.rgb *= ipbrRefScale;
				#endif
			#endif
			#if defined DEFERRED_BACKGROUND_REFLECTION || defined FORWARD_BACKGROUND_REFLECTION
				specularReflections = mix(DarkenedDiffuseLighting, backgroundReflection, backgroundReflectMask);
			#endif
			#if defined WSR_DEFER_FORWARD && defined FORWARD_SPECULAR && (DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0)
				if (!isHand && !mirrorSkyOnly) {
					wsrDeferBase = specularReflections;
					wsrDeferWeight = dot(F0, vec3(1.0 / 3.0)) * (1.0 - enviornmentReflection.a) * (1.0 - reflectionVisibilty);
					wsrDeferDir = normalize(reflectedVector_L);
				}
			#endif
			#if DEFERRED_SSR_QUALITY > 0 || FORWARD_SSR_QUALITY > 0
				specularReflections = mix(specularReflections, enviornmentReflection.rgb, enviornmentReflection.a);
			#endif

			#if IPBR_MODE == 1 && defined DEFERRED_SPECULAR && !defined FORWARD_SPECULAR
				if (!isMetal) {
					// Upstream's lighting spans ~2-3x between sun and shade; Bliss' HDR spans 10x+, so a sunlit hit (or a torch)
					// mirrored onto a shaded block turns into bright speckles. Soft-cap reflections relative to the local light.
					const vec3 lumaW = vec3(0.299, 0.587, 0.114);
					float localLight = dot(diffuseLighting, lumaW) / max(dot(albedo, lumaW), 0.02);
					float refCap = 2.5 * localLight + 1e-5;
					float refLum = dot(specularReflections, lumaW);
					specularReflections *= 1.0 / (1.0 + refLum / refCap);

					// Upstream's texturePreservation (composite1.glsl): dark reflections do not darken the surface.
					specularReflections = mix(specularReflections, max(DarkenedDiffuseLighting, specularReflections), 0.7);
				}
			#endif

			specularReflections = mix(DarkenedDiffuseLighting, specularReflections, F0);

			// lerp back to diffuse lighting if the reflection has not been deemed visible enough
			specularReflections = mix(specularReflections, diffuseLighting, reflectionVisibilty);
		}
	#endif

	#if defined OVERWORLD_SHADER || SUN_SPECULAR_MULT > 0
		#if IPBR_MODE == 1 && defined DEFERRED_SPECULAR && !defined FORWARD_SPECULAR
			vec3 lightSourceReflection;
			if (ipbrDielectric) {
				// Intense-fresnel materials carry highlightMult ~2-3.5 upstream; the rest default to 1.
				float highlightMult = ipbrIntense ? 2.5 : 1.0;
				lightSourceReflection = SUN_SPECULAR_MULT * lightColor * IpbrHighlight(normal, playerPos, lightPos, ipbrSmoothnessG) * highlightMult;
			} else {
				lightSourceReflection = SUN_SPECULAR_MULT * lightColor * GGX(normal, -playerPos, lightPos, highlightRoughness, reflectance, metalAlbedoTint);
			}
		#else
			vec3 lightSourceReflection = SUN_SPECULAR_MULT * lightColor * GGX(normal, -playerPos, lightPos, roughness, reflectance, metalAlbedoTint);
		#endif
		specularReflections += lightSourceReflection;
	#endif

	#if defined FLASHLIGHT_SPECULAR && (defined DEFERRED_SPECULAR || defined FORWARD_SPECULAR)
		vec3 flashLightReflection = vec3(FLASHLIGHT_R,FLASHLIGHT_G,FLASHLIGHT_B) * flashLight_stuff.a * GGX(normal, -flashLight_stuff.xyz, -flashLight_stuff.xyz, roughness, reflectance, metalAlbedoTint);
		specularReflections += flashLightReflection;
	#endif

	return specularReflections;
}