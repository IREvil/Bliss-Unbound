#include "/lib/settings.glsl"

// REFL_PREPASS: this file is also compiled as the reduced-resolution reflection compute shaders (world0/composite2_a/_b.csh).
#ifdef REFL_PREPASS
	#define FLAT_IN
	#define FRAGCOORD prepassFragCoord
#else
	#define FLAT_IN flat varying
	#define FRAGCOORD gl_FragCoord
#endif
// #if defined END_SHADER || defined NETHER_SHADER
// 	#undef IS_LPV_ENABLED
// #endifs

#ifdef IS_LPV_ENABLED
	#extension GL_ARB_shader_image_load_store: enable
	#extension GL_ARB_shading_language_packing: enable
#endif
#if COLORED_LIGHTING_INTERNAL > 0
	#extension GL_ARB_shader_image_load_store: enable
	#if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
		#extension GL_ARB_shader_storage_buffer_object: enable
		#extension GL_ARB_shading_language_420pack: enable
		#extension GL_ARB_gpu_shader5: enable
		#extension GL_ARB_shading_language_packing: enable
	#endif
#endif

#include "/lib/util.glsl"
#include "/lib/res_params.glsl"

#ifdef REFL_PREPASS
	vec4 prepassFragCoord = vec4(0.0);
#endif


#define diagonal3_old(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD_old(m, v) (diagonal3_old(m) * (v) + (m)[3].xyz)

const bool colortex5MipmapEnabled = true;
uniform float nightVision;

#ifdef OVERWORLD_SHADER
	const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadow;

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex0;
		uniform sampler2DShadow shadowtex1;
	#endif

	FLAT_IN vec3 averageSkyCol_Clouds;
	FLAT_IN vec4 lightCol;
	FLAT_IN vec3 moonCol;

	#if SUN_SPECULAR_MULT != 0
		#define LIGHTSOURCE_REFLECTION
	#endif
	
	#include "/lib/lightning_stuff.glsl"
#endif

#ifdef NETHER_SHADER
	const bool colortex4MipmapEnabled = true;
	uniform vec3 lightningEffect;
	#undef LIGHTSOURCE_REFLECTION
#endif

#ifdef END_SHADER
	uniform vec3 lightningEffect;
	
	FLAT_IN float Flashing;
	#undef LIGHTSOURCE_REFLECTION
#endif

uniform int hideGUI;
uniform sampler2D noisetex; //noise
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex;
uniform sampler2D dhDepthTex1;
#endif

uniform sampler2D colortex0; //clouds
uniform sampler2D colortex1; //albedo(rgb),material(alpha) RGBA16
uniform sampler2D colortex2; //translucents(rgba)
uniform sampler2D colortex3; //filtered shadowmap(VPS)
uniform sampler2D colortex4; //LUT(rgb), quarter res depth(alpha)
uniform sampler2D colortex5; //TAA buffer/previous frame
uniform sampler2D colortex6; //Noise
uniform sampler2D colortex7; //water?
uniform sampler2D colortex8; //Specular
// uniform sampler2D colortex9; //Specular
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex15; // flat normals(rgb), vanillaAO(alpha)

#ifdef IS_LPV_ENABLED
	uniform usampler1D texBlockData;
	uniform sampler3D texLpv1;
	uniform sampler3D texLpv2;
#endif

uniform mat4 gbufferPreviousModelView;

// uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float updateFadeTime;
// uniform float centerDepthSmooth;

// uniform float far;
uniform float near;
uniform float farPlane;
uniform float dhFarPlane;
uniform float dhNearPlane;

FLAT_IN vec3 zMults;

uniform vec2 texelSize;
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;

uniform float eyeAltitude;
FLAT_IN vec2 TAA_Offset;

uniform int frameCounter;
uniform float frameTimeCounter;

uniform float rainStrength;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;

uniform vec3 sunVec;
FLAT_IN vec3 WsunVec;
FLAT_IN vec3 unsigned_WsunVec;
FLAT_IN vec3 WmoonVec;
FLAT_IN float exposure;
FLAT_IN vec3 albedoSmooth;

#ifdef IS_LPV_ENABLED
	uniform int heldItemId;
	uniform int heldItemId2;
#endif



uniform float waterEnteredAltitude;

void convertHandDepth(inout float depth) {
    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    depth = ndcDepth * 0.5 + 0.5;
}

float convertHandDepth_2(in float depth, bool hand) {
	if(!hand) return depth;

    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    return ndcDepth * 0.5 + 0.5;
}

#include "/lib/projections.glsl"

// Complementary's ACT light volume, read side.  The volume is written by the
// shadow programs and floodfilled by shadowcomp; this is where its light is
// finally applied to shading.  IS_LPV_ENABLED is off whenever this is on, so
// only one light path is ever active.
//
// Placed after lib/projections.glsl because lightVoxelization.glsl's SceneToVoxel
// reads cameraPosition at file scope, and projections.glsl is what declares it.
#if COLORED_LIGHTING_INTERNAL > 0
	uniform usampler3D voxel_sampler;

	// lightVoxelization.glsl also carries the write path, which references
	// floodfill_sampler and framemod2 even though this program never calls it --
	// GLSL needs every referenced identifier declared.
	uniform sampler3D floodfill_sampler;
	uniform sampler3D floodfill_sampler_copy;
	uniform int framemod2;
	// Iris 1.8+ can supply cameraPositionFract, but it is not declared in every
	// program, and this must compile wherever the voxeliser is used.  fract of
	// cameraPosition is equivalent and always available.
	vec3 cameraPositionBestFract = fract(cameraPosition);

	#include "/lib/voxelization/act_common.glsl"
	#include "/lib/colors/blocklightColors.glsl"
	#include "/lib/voxelization/lightVoxelization.glsl"
#endif
#include "/lib/color_transforms.glsl"
#include "/lib/waterBump.glsl"
#include "/lib/Shadow_Params.glsl"
#include "/lib/Shadows.glsl"
#include "/lib/stars.glsl"
#include "/lib/sky_gradient.glsl"

#ifdef OVERWORLD_SHADER

	#include "/lib/scene_controller.glsl"
	
	#define CLOUDSHADOWSONLY
	#include "/lib/volumetricClouds.glsl"
	#define CLOUDS_INTERSECT_TERRAIN
#endif

#ifdef IS_LPV_ENABLED
	#include "/lib/hsv.glsl"
	#include "/lib/lpv_common.glsl"
	#include "/lib/lpv_render.glsl"
#endif

#define DEFERRED_SPECULAR
#define DEFERRED_SSR_QUALITY 30 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 200 300 400 500]
// Same option as the water pass: water and glass reflections are traced here when deferred.
#define FORWARD_SSR_QUALITY 30 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 200 300 400 500]
#define DEFERRED_BACKGROUND_REFLECTION
#define DEFERRED_ROUGH_REFLECTION

#ifdef DEFERRED_SPECULAR
#endif
#if DEFERRED_SSR_QUALITY > -1
#endif
#ifdef DEFERRED_BACKGROUND_REFLECTION
#endif
#ifdef DEFERRED_ROUGH_REFLECTION
#endif

#include "/lib/voxelization/blissWSR.glsl"
#if defined INCLUDE_BLISS_WSR && defined WSR_TRANSLUCENT_DEFERRED && defined OVERWORLD_SHADER
	#define WSR_DEFER_RESOLVE
	layout(rgba32ui) uniform readonly uimage2D wsrTrans_img;
#endif
// Only world0 runs the reflection prepass (REFL_PREPASS_AVAILABLE comes from its entry files); elsewhere the
// reflections are traced inline. 100% is not a reduced resolution: there the prepass would trace the same one ray
// per screen pixel and then upsample it, so the inline path is both cheaper and identical to it.
#if defined REFL_PREPASS_AVAILABLE && defined REFLECTION_PREPASS_ON && defined INCLUDE_BLISS_WSR && defined OVERWORLD_SHADER
	// Side of the upsample's tap grid: the widest blur a fully rough surface can average, and with it the cost.
	#if REFLECTION_BLUR == 0
		#define REFL_BLUR_SIDE 1
	#elif REFLECTION_BLUR == 25
		#define REFL_BLUR_SIDE 2
	#elif REFLECTION_BLUR == 50
		#define REFL_BLUR_SIDE 3
	#elif REFLECTION_BLUR == 75
		#define REFL_BLUR_SIDE 4
	#else
		#define REFL_BLUR_SIDE 5
	#endif
	#if REFLECTION_RES_WORLD < 100
		#define REFL_PREPASS_WORLD
	#endif
	#if defined WSR_DEFER_RESOLVE && REFLECTION_RES_MIRROR < 100
		#define REFL_PREPASS_MIRROR
	#endif
	// The roughness blur of the reduced-resolution reflection (world0/composite2_c/_d.csh). A rough surface reflects
	// a cone, not a ray, and averaging the reduced-resolution texels around the pixel is the only way to gather
	// enough of that cone cheaply: the passes run on the reduced grid, so one tap costs a fraction of a traced ray.
	// The width is given in screen pixels and converted to reduced-resolution texels, so the blur looks the same at
	// every resolution setting.
	//
	// Iris collects a program's extra compute passes as <program>_a.csh, _b.csh, _c.csh ... and STOPS AT THE FIRST
	// MISSING LETTER (ProgramSet.readComputeArray breaks when the source is null). The letters therefore have to stay
	// contiguous from _a: a gap silently drops every later pass, which is what happened when the blur was shipped as
	// _d/_e with no _c. composite2's chain is now _a (blocks), _b (water/glass), _c (blur, horizontal), _d (blur,
	// vertical). Keep it that way if a pass is ever removed.
	#if defined REFL_PREPASS_WORLD && REFLECTION_BLUR > 0
		#define REFL_BLUR_AVAILABLE
		#if REFLECTION_BLUR == 25
			#define REFL_BLUR_PX 12.0
		#elif REFLECTION_BLUR == 50
			#define REFL_BLUR_PX 32.0
		#elif REFLECTION_BLUR == 75
			#define REFL_BLUR_PX 64.0
		#else
			#define REFL_BLUR_PX 128.0
		#endif
	#endif
	#if REFL_PREPASS == 1
		layout(rgba16f) uniform writeonly image2D reflWorld_img;
		#ifdef REFL_BLUR_AVAILABLE
			// Also written here, so that a missing or empty blur pass can only ever cost smoothness, never the
			// reflection itself: the trace's own value is already in the image the lighting pass reads.
			layout(rgba16f) uniform writeonly image2D reflWorldBlur_img;
		#endif
	#elif REFL_PREPASS == 2
		layout(rgba16f) uniform writeonly image2D reflMirror_img;
	#elif REFL_PREPASS == 3
		layout(rgba16f) uniform readonly image2D reflWorld_img;
		layout(rgba16f) uniform writeonly image2D reflWorldBlurTmp_img;
	#elif REFL_PREPASS == 4
		layout(rgba16f) uniform readonly image2D reflWorldBlurTmp_img;
		layout(rgba16f) uniform writeonly image2D reflWorldBlur_img;
	#else
		#ifdef REFL_PREPASS_WORLD
			layout(rgba16f) uniform readonly image2D reflWorld_img;
		#endif
		#ifdef REFL_BLUR_AVAILABLE
			layout(rgba16f) uniform readonly image2D reflWorldBlur_img;
		#endif
		#ifdef REFL_PREPASS_MIRROR
			layout(rgba16f) uniform readonly image2D reflMirror_img;
		#endif
	#endif
#endif
#include "/lib/specular.glsl"
#include "/lib/diffuse_lighting.glsl"

#include "/lib/end_fog.glsl"
#include "/lib/DistantHorizons_projections.glsl"

float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}

vec3 decode (vec2 encn){
    vec3 n = vec3(0.0);
    encn = encn * 2.0 - 1.0;
    n.xy = abs(encn);
    n.z = 1.0 - n.x - n.y;
    n.xy = n.z <= 0.0 ? (1.0 - n.yx) * sign(encn) : encn;
    return clamp(normalize(n.xyz),-1.0,1.0);
}

vec2 decodeVec2(float a){
    const vec2 constant1 = 65535. / vec2( 256., 65536.);
    const float constant2 = 256. / 255.;
    return fract( a * constant1 ) * constant2 ;
}
float DH_ld(float dist) {
    return (2.0 * dhNearPlane) / (dhFarPlane + dhNearPlane - dist * (dhFarPlane - dhNearPlane));
}

float DH_inv_ld (float lindepth){
	return -((2.0*dhNearPlane/lindepth)-dhFarPlane-dhNearPlane)/(dhFarPlane-dhNearPlane);
}

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
    return (near * far) / (depth * (near - far) + far);
	// return (2.0 * near) / (far + near - depth * (far - near));
}

float invertlinearDepthFast(const in float depth, const in float near, const in float far) {
	return ((2.0*near/depth)-far-near)/(far-near);
}


float triangularize(float dither)
{
    float center = dither*2.0-1.0;
    dither = center*inversesqrt(abs(center));
    return clamp(dither-fsign(center),0.0,1.0);
}

vec3 fp10Dither(vec3 color,float dither){
	const vec3 mantissaBits = vec3(6.,6.,5.);
	vec3 exponent = floor(log2(color));
	return color + dither*exp2(-mantissaBits)*exp2(exponent);
}

float interleaved_gradientNoise_temporal(){
	#ifdef TAA
		return fract(52.9829189*fract(0.06711056*FRAGCOORD.x + 0.00583715*FRAGCOORD.y ) + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(52.9829189*fract(0.06711056*FRAGCOORD.x + 0.00583715*FRAGCOORD.y ) + 1.0/1.6180339887);
	#endif
}

float interleaved_gradientNoise(){
	vec2 coord = FRAGCOORD.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}

float R2_dither(){
	vec2 coord = FRAGCOORD.xy ;

	#ifdef TAA
		coord += (frameCounter%40000) * 2.0;
	#endif
	
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * coord.x + alpha.y * coord.y ) ;
}

float R2_dither2(){
	vec2 coord = FRAGCOORD.xy ;

	#ifdef TAA
		coord += (frameCounter*8)%40000;
	#endif
	
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * coord.x + alpha.y * coord.y ) ;
}

float blueNoise(){
	#ifdef TAA
  		return fract(texelFetch2D(noisetex, ivec2(FRAGCOORD.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(texelFetch2D(noisetex, ivec2(FRAGCOORD.xy)%512, 0).a + 1.0/1.6180339887);
	#endif
}

vec4 blueNoise(vec2 coord){
  return texelFetch2D(colortex6, ivec2(coord)%512 , 0) ;
}

vec2 CleanSample(
	int samples, float totalSamples, float noise
){

	// this will be used to make 1 full rotation of the spiral. the mulitplication is so it does nearly a single rotation, instead of going past where it started
	float variance = noise * 0.897;

	// for every sample input, it will have variance applied to it.
	float variedSamples = float(samples) + variance;
	
	// for every sample, the sample position must change its distance from the origin.
	// otherwise, you will just have a circle.
    float spiralShape = sqrt(variedSamples / (totalSamples + variance));

	float shape = 2.26; // this is very important. 2.26 is very specific
    float theta = variedSamples * (PI * shape);

	float x =  cos(theta) * spiralShape;
	float y =  sin(theta) * spiralShape;

    return vec2(x, y);
}

vec3 viewToWorld(vec3 viewPos) {
    vec4 pos;
    pos.xyz = viewPos;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}

vec3 worldToView(vec3 worldPos) {
    vec4 pos = vec4(worldPos, 0.0);
    pos = gbufferModelView * pos;
    return pos.xyz;
}

float swapperlinZ(float depth, float _near, float _far) {
    return (2.0 * _near) / (_far + _near - depth * (_far - _near));
	// l = (2*n)/(f+n-d(f-n))
	// f+n-d(f-n) = 2n/l
	// -d(f-n) = ((2n/l)-f-n)
	// d = -((2n/l)-f-n)/(f-n)

}

// vec2 SSRT_Shadows(vec3 viewPos, bool depthCheck, vec3 lightDir, float noise, bool isSSS, bool hand){
	

// 	float handSwitch = hand ? 1.0 : 0.0;

//     float steps = 16.0;
// 	float Shadow = 1.0; 
// 	float SSS = 0.0;
// 	// isSSS = true;

// 	float _near = near; float _far = far*4.0;

// 	if (depthCheck) {
// 		_near = dhNearPlane;
// 		_far = dhFarPlane;
// 	}
    

// 	vec3 clipPosition = toClipSpace3_DH(viewPos, depthCheck);
// 	//prevents the ray from going behind the camera
// 	float rayLength = ((viewPos.z + lightDir.z * _far*sqrt(3.)) > -_near) ?
//       				  (-_near -viewPos.z) / lightDir.z : _far*sqrt(3.);

//     vec3 direction = toClipSpace3_DH(viewPos + lightDir*rayLength, depthCheck) - clipPosition;  //convert to clip space

//     direction.xyz = direction.xyz / max(abs(direction.x)/0.0005, abs(direction.y)/0.0005);	//fixed step size

// 	// float Stepmult = depthCheck ? (isSSS ? 1.0 : 3.0) : (isSSS ? 1.0 : 3.0);
// 	float Stepmult = isSSS ? 3.0 : 6.0;

//     vec3 rayDir = direction * Stepmult * vec3(RENDER_SCALE,1.0);
// 	vec3 screenPos = clipPosition * vec3(RENDER_SCALE,1.0) + rayDir*noise - (isSSS ? rayDir*0.9 : vec3(0.0));

// 	float minZ = screenPos.z - 1.0;
// 	float maxZ = screenPos.z;

// 	// as distance increases, add larger values to the SSS value. this scales the "density" with distance, as far things should appear denser.
// 	float dist = 1.0 + length(mat3(gbufferModelViewInverse) * viewPos) / 500.0;

// 	for (int i = 0; i < int(steps); i++) {
		
// 		float samplePos = convertHandDepth_2(texture2D(depthtex1, screenPos.xy).x, hand);
		
// 		#ifdef DISTANT_HORIZONS
// 			if(depthCheck) samplePos = texture2D(dhDepthTex1, screenPos.xy).x;
// 		#endif

// 		if(samplePos < screenPos.z && (samplePos <= max(minZ,maxZ) && samplePos >= min(minZ,maxZ))){
// 			vec2 linearZ = vec2(swapperlinZ(screenPos.z, _near, _far), swapperlinZ(samplePos, _near, _far));
// 			float calcthreshold = abs(linearZ.x - linearZ.y) / linearZ.x;

// 			if (calcthreshold < 0.035) Shadow = 0.0;
// 			SSS += dist;
// 		} 
		
// 		minZ = maxZ - (isSSS ? 1.0 : 0.0001) / swapperlinZ(samplePos, _near, _far);
// 		maxZ += rayDir.z;

// 		screenPos += rayDir;
// 	}

// 	return vec2(Shadow, SSS / steps);
// }

vec2 SSRT_Shadows(vec3 viewPos, bool depthCheck, vec3 lightDir, float noise, bool isSSS, bool hand){

	// return 1.0;

	float shadows = 1.0;
	float samples = 16.0;
	float SSS = 0.0;

	float _near = near; float _far = far*4.0;

	if (depthCheck) {
		_near = dhNearPlane;
		_far = dhFarPlane;
	}
    
    vec3 position = toClipSpace3_DH(viewPos, depthCheck) ;
	
	//prevents the ray from going behind the camera
	float rayLength = ((viewPos.z + lightDir.z * _far * sqrt(3.)) > -_near) ? (-_near - viewPos.z) / lightDir.z : _far * sqrt(3.);

    vec3 direction = toClipSpace3_DH(viewPos + lightDir*rayLength, depthCheck) - position;
    direction.xyz = direction.xyz / max(max(abs(direction.x)/0.0005, abs(direction.y)/0.0005),400.0);	//fixed step size
	direction *= 6.0;

	position.xy *= RENDER_SCALE;
	direction.xy *= RENDER_SCALE;
	
	vec3 newPos = position + direction*noise;
	// literally shadow bias to fight shadow acne due to precision problems when comparing sampled depth and marched position
	newPos += direction*0.3;

	float SSSdistanceScale = 1.0 / (1.0 + swapperlinZ(position.z, _near, _far)*32.0);
	float distanceScale2 = 1.0 + length(mat3(gbufferModelViewInverse) * viewPos) / 150.0;

	for (int i = 0; i < int(samples); i++) { 
		
		float sampleDepth = convertHandDepth_2(texelFetch2D(depthtex1, ivec2(newPos.xy/texelSize),0).x,hand);
		
		#ifdef DISTANT_HORIZONS
			if(depthCheck) sampleDepth = texelFetch2D(dhDepthTex1, ivec2(newPos.xy/texelSize),0).x;
		#endif

		if(sampleDepth < newPos.z){
			float linearCurrentPos = swapperlinZ(newPos.z, _near, _far);
			float linearSampledDepth = swapperlinZ(sampleDepth, _near, _far);

			float dist = abs(linearSampledDepth - linearCurrentPos) / linearCurrentPos;
			
			// if (dist < 0.035){
			if (dist < 0.035/(1.0+linearCurrentPos) && (sampleDepth < newPos.z )) shadows = 0.0;

			// if (dist < 0.3/(1.0+linearCurrentPos)) SSS += distanceScale2;
			if (dist < SSSdistanceScale) SSS += distanceScale2;
		}

		newPos += direction;
		
	}
	return vec2(shadows, SSS / samples );
}

float SSRT_FlashLight_Shadows(vec3 viewPos, bool depthCheck, vec3 lightDir, float noise){
	

    float steps = 16.0;
	float Shadow = 1.0; 
	float SSS = 0.0;
	// isSSS = true;

	float _near = near; float _far = far*4.0;

	if (depthCheck) {
		_near = dhNearPlane;
		_far = dhFarPlane;
	}
    

	vec3 clipPosition = toClipSpace3_DH(viewPos, depthCheck);
	//prevents the ray from going behind the camera
	float rayLength = ((viewPos.z + lightDir.z * _far*sqrt(3.)) > -_near) ?
      				  (-_near -viewPos.z) / lightDir.z : _far*sqrt(3.);

    vec3 direction = toClipSpace3_DH(viewPos + lightDir*rayLength, depthCheck) - clipPosition;  //convert to clip space

    direction.xyz = direction.xyz / max(abs(direction.x)/0.0005, abs(direction.y)/0.0005);	//fixed step size

	float Stepmult = 6.0;

    vec3 rayDir = direction * Stepmult * vec3(RENDER_SCALE,1.0);
	vec3 screenPos = clipPosition * vec3(RENDER_SCALE,1.0) + rayDir*noise;


	for (int i = 0; i < int(steps); i++) {
		
		float samplePos = texture2D(depthtex2, screenPos.xy).x;
		
		#ifdef DISTANT_HORIZONS
			if(depthCheck) samplePos = texture2D(dhDepthTex1, screenPos.xy).x;
		#endif

		if(samplePos < screenPos.z){// && (samplePos <= max(minZ,maxZ) && samplePos >= min(minZ,maxZ))){
			// vec2 linearZ = vec2(swapperlinZ(screenPos.z, _near, _far), swapperlinZ(samplePos, _near, _far));
			// float calcthreshold = abs(linearZ.x - linearZ.y) / linearZ.x;

			// if (calcthreshold < 0.035) 
			Shadow = 0.0;
		} 
	
		screenPos += rayDir;
	}

	return Shadow;
}

void Emission(
	inout vec3 Lighting,
	vec3 Albedo,
	float Emission
){
	if( Emission < 254.5/255.0) Lighting = mix(Lighting, Albedo * 5.0 * Emissive_Brightness, pow(Emission, Emissive_Curve));
}

#include "/lib/indirect_lighting_effects.glsl"
#include "/lib/PhotonGTAO.glsl"

void doEdgeAwareBlur(
	sampler2D tex1, sampler2D tex2, sampler2D depth,
	float referenceDepth, bool hand,
	inout vec2 ambientEffects, inout vec3 filteredShadow
){
	float threshold = clamp(referenceDepth*referenceDepth*0.5,0.0001,0.005);
	vec3 shadow_RESULT = vec3(0.0);
	vec2 ssao_RESULT = vec2(0.0);
	float edgeSum = 0.0;

	vec2 coord = FRAGCOORD.xy - 1.5;
	ivec2 UV = ivec2(coord);
	ivec2 UV_NOISE = ivec2(FRAGCOORD.xy*texelSize + 1);

	ivec2 OFFSET[4] = ivec2[](
	  ivec2(-1,-1),
	  ivec2( 1, 1),
	  ivec2(-1, 1),
	  ivec2( 1,-1)
	);

	for(int i = 0; i < 4; i++) {
		#ifdef DISTANT_HORIZONS
			float offsetDepth = sqrt(texelFetch2D(depth, UV + OFFSET[i] + UV_NOISE,0).a/65000.0);
		#else
			float offsetDepth = ld(convertHandDepth_2(texelFetch2D(depth, UV + OFFSET[i] + UV_NOISE, 0).r,hand));
		#endif

		float edgeDiff = abs(offsetDepth - referenceDepth) < threshold ? 1.0 : 1e-7;

		#ifdef Variable_Penumbra_Shadows
			shadow_RESULT += texelFetch2D(tex1, UV + OFFSET[i] + UV_NOISE, 0).rgb*edgeDiff;
		#endif
		// #if indirect_effect == 1
			ssao_RESULT += texelFetch2D(tex2, UV + OFFSET[i] + UV_NOISE, 0).rg*edgeDiff;
		// #endif

		edgeSum += edgeDiff;
	}
	// sample without an offset with texture filtering to get a slightly blurred sample. make sure to average without skewing the rest of the average.
	filteredShadow = shadow_RESULT/edgeSum * 0.8 + 0.2 * texture2D(tex1, texelSize*FRAGCOORD.xy).rgb;
	ambientEffects =   ssao_RESULT/edgeSum * 0.8 + 0.2 * texture2D(tex2, texelSize*FRAGCOORD.xy).rg;
	// ambientEffects.x = edgeSum / 4.0;

}

vec4 BilateralUpscale_VLFOG(sampler2D tex, sampler2D depth, float referenceDepth){

	vec4 colorSum = vec4(0.0);
	float edgeSum = 0.0;

	#ifdef DISTANT_HORIZONS
		float threshold = referenceDepth * mix(0.5,  0.05, min(max(0.1 - referenceDepth,0)/0.1,1));
	#else
		float threshold = referenceDepth * 0.05;
	#endif

	vec2 coord = FRAGCOORD.xy - 1.5;
	vec2 UV = coord;
	const ivec2 SCALE = ivec2(1.0/VL_RENDER_RESOLUTION);
	ivec2 UV_DEPTH = ivec2(UV*VL_RENDER_RESOLUTION)*SCALE;
	ivec2 UV_COLOR = ivec2(UV*VL_RENDER_RESOLUTION);
	ivec2 UV_NOISE = ivec2(FRAGCOORD.xy*texelSize + 1);

	ivec2 OFFSET[5] = ivec2[](
	  ivec2(-1,-1),
	  ivec2( 1, 1),
	  ivec2(-1, 1),
	  ivec2( 1,-1),
	  ivec2( 0, 0)
	);

	for(int i = 0; i < 4; i++) {
		#ifdef DISTANT_HORIZONS
			float offsetDepth = sqrt(texelFetch2D(depth, UV_DEPTH + (OFFSET[i] + UV_NOISE) * SCALE,0).a/65000.0);
		#else
			float offsetDepth = ld(texelFetch2D(depth, UV_DEPTH + (OFFSET[i] + UV_NOISE) * SCALE, 0).r);
		#endif

		float edgeDiff = abs(offsetDepth - referenceDepth) < threshold ? 1.0 : 1e-7;
		vec4 offsetColor = texelFetch2D(tex, UV_COLOR + OFFSET[i] + UV_NOISE, 0).rgba;
		colorSum += offsetColor*edgeDiff;
		edgeSum += edgeDiff;
	}

	return colorSum/edgeSum;
}

#ifdef OVERWORLD_SHADER

vec3 ComputeShadowMap_COLOR(in vec3 projectedShadowPosition, float distortFactor, float noise, float shadowBlockerDepth, float NdotL, float maxDistFade, vec3 directLightColor, inout float FUNNYSHADOW, inout vec3 tintedSunlight, bool isSSS ,inout float shadowDebug){

	// if(maxDistFade <= 0.0) return 1.0;
	float backface = NdotL <= 0.0 ? 1.0 : 0.0;

	vec3 shadowColor = vec3(0.0);
	vec3 translucentTint = vec3(0.0);

	#ifdef BASIC_SHADOW_FILTER
		int samples = SHADOW_FILTER_SAMPLE_COUNT;
		float rdMul = (shadowBlockerDepth*distortFactor*d0*k/shadowMapResolution) * 0.3;
		
		for(int i = 0; i < samples; i++){
			vec2 offsetS = CleanSample(i, samples - 1, noise) * rdMul;
			projectedShadowPosition.xy += offsetS;
	#else
		int samples = 1;
	#endif

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		float opaqueShadow = shadow2D(shadowtex0, projectedShadowPosition).x;
		float opaqueShadowT = shadow2D(shadowtex1, projectedShadowPosition).x;
		vec4 translucentShadow = texture2D(shadowcolor0, projectedShadowPosition.xy);

		float shadowAlpha = pow(1.0-pow(1.0-translucentShadow.a,2.0),5.0);
		translucentShadow.rgb = normalize(translucentShadow.rgb*translucentShadow.rgb + 0.0001) * (1.0-shadowAlpha);

		// translucentTint += mix(translucentShadow.rgb * mix(opaqueShadowT, 1.0, backface), vec3(1.0), max(opaqueShadow, backface * (shadowAlpha < 1.0 ? 0.0 : 1.0)));
		
		shadowColor += directLightColor * mix(translucentShadow.rgb * opaqueShadowT, vec3(1.0), opaqueShadow);
		
		translucentTint += mix(translucentShadow.rgb, vec3(1.0), max(opaqueShadow, backface * (shadowAlpha < 1.0 ? 0.0 : 1.0)));
		FUNNYSHADOW += ((1.0-shadowAlpha) * opaqueShadowT)/samples;
	#else
		// shadowColor += directLightColor * shadow2D(shadow, projectedShadowPosition).x;
		shadowColor += vec3(1.0) * shadow2D(shadow, projectedShadowPosition).x;
	#endif


	#ifdef BASIC_SHADOW_FILTER
		}
	#endif

	#ifdef debug_SHADOWMAP
		shadowDebug = shadow2D(shadow, projectedShadowPosition).x;
	#endif
	// #ifdef TRANSLUCENT_COLORED_SHADOWS
		// directLightColor *= mix(vec3(1.0), translucentTint.rgb / samples, maxDistFade);
		tintedSunlight *= translucentTint.rgb / samples;
	// #endif

	return shadowColor.rgb / samples;
	// return mix(directLightColor, shadowColor.rgb / samples, maxDistFade);

}

#endif

float CustomPhase(float LightPos){

	float PhaseCurve = 1.0 - LightPos;
	float Final = exp2(sqrt(PhaseCurve) * -25.0);
	Final += exp(PhaseCurve * -10.0)*0.5;

	return Final;
}

vec3 SubsurfaceScattering_sun(vec3 albedo, float Scattering, float Density, float lightPos, float SS_shadows, float distantSSS, bool hand){
	
	// Density = 1.0;
	Scattering *= sss_density_multiplier;

	float density = 1e-6 + Density*2.0;
	float scatterDepth = max(1.0 - Scattering/density, 0.0);
	scatterDepth *= exp(-7.0 * (1.0-scatterDepth));

	scatterDepth = scatterDepth * mix(exp(-4.0 * SS_shadows), 1.0, (1.0-SCREENSPACE_DIRECT_SSS_BLENDING) * scatterDepth * distantSSS);
	
	if(hand) scatterDepth = max(1.0 - Scattering*10.0, 0.0) * exp(-4.0 * SS_shadows);

	vec3 absorbColor = exp(max(luma(albedo) - albedo*vec3(1.0,1.1,1.2), 0.0) * -20.0 * sss_absorbance_multiplier);
	vec3 scatter = scatterDepth * mix(absorbColor, vec3(1.0), scatterDepth);
	
	#if SSS_TYPE == 3
		scatter *= pow(Density, LabSSS_Curve);
	#else
		if(Density < 0.01) scatter = vec3(0.0);
	#endif
	
	scatter *= 1.0 + CustomPhase(lightPos)*6.0; // ~10x brighter at the peak

	return scatter;	
}

vec3 SubsurfaceScattering_sky(vec3 albedo, float Scattering, float Density){
	// Density = 1.0;
	#ifdef OLD_INDIRECT_SSS
		float scatterDepth = 1.0 - pow(1.0-Scattering, 0.5 + Density * 2.5);
		vec3 absorbColor = vec3(1.0) * exp(-(15.0 - 10.0*scatterDepth)  * sss_absorbance_multiplier * 0.01);
		vec3 scatter =  scatterDepth *  absorbColor * pow(Density, LabSSS_Curve);
	#else
		float scatterDepth = pow(Scattering,3.5);
		scatterDepth = 1.0-pow(1.0-scatterDepth,5.0);

		vec3 absorbColor = exp(max(luma(albedo) - albedo*vec3(1.0,1.1,1.2), 0.0) * -20.0 * sss_absorbance_multiplier);
		vec3 scatter = scatterDepth * mix(absorbColor, vec3(1.0), scatterDepth) * pow(Density, LabSSS_Curve);
	#endif

	// scatter *= 1.0 + exp(-7.0*(-playerPosNormalized.y*0.5+0.5));

	return scatter;
}

uniform float wetnessAmount;
uniform float wetness;

void applyPuddles(
	in vec3 worldPos, in vec3 flatNormals, in float lightmap, in bool isWater, inout vec3 albedo, inout vec3 normals, inout float roughness, inout float f0
){
	vec3 unchangedNormals = normals;



	float halfWet = min(wetnessAmount,1.0);
	float fullWet = clamp(wetnessAmount - 2.0,0.0,1.0);
	// halfWet = 1.0;
 	// fullWet = 0.0;
	vec2 driprate = vec2(0.0,frameTimeCounter)*0.05;

	vec2 UV = mix(worldPos.xz, worldPos.xy*vec2(2.0, 0.5)+driprate, abs(flatNormals.z));
	UV = mix(UV, worldPos.zy*vec2(2.0, 0.5)+driprate, abs(flatNormals.x));

	float noise = texture2D(noisetex, UV * 0.02).b;


	float lightmapMax = min(max(lightmap - 0.9,0.0) * 10.0,1.0) ;
	float lightmapMin = min(max(lightmap - 0.8,0.0) * 5.0,1.0) ;
	lightmap = clamp(lightmapMax + noise*lightmapMin*2.0,0.0,1.0);
	lightmap = pow(1.0-pow(1.0-lightmap,3.0),2.0);
	
	float puddles = max(halfWet - noise,0.0);
	puddles = clamp(halfWet - exp(-25.0 * puddles*puddles*puddles*puddles*puddles),0.0,1.0);
	
	float wetnessStages = mix(puddles, 1.0, fullWet) * lightmap;
	if(isWater) wetnessStages = 0.0;

	normals = mix(normals, flatNormals, puddles * lightmap * clamp(flatNormals.y,0.0,1.0));
	roughness = mix(roughness, 1.0, wetnessStages);

	if(f0 < 229.5/255.0 ) albedo = pow(albedo * (1.0 - 0.08*wetnessStages), vec3(1.0 + 0.7*wetnessStages));

	//////////////// snow
	
	// float upnormal = clamp(-(normals / dot(abs(normals),vec3(1.0))).y+clamp(flatNormals.y,0.5,1.0),0,1);
	// halfWet = clamp(halfWet - upnormal - (1.0-lightmap),0.0,1.0);
	// float snow = max(halfWet - noise,0.0);
	// snow = clamp(halfWet - exp(-20.0 * snow*snow*snow*snow*snow),0.0,1.0);
	
	// if(isWater || f0 > 229.5/255.0) snow = 0.0;

	// normals = mix(normals, unchangedNormals, snow);
	// roughness = mix(roughness, 0.5, snow);
	// albedo = mix(albedo, vec3(1.0), snow);
}


#if (defined REFL_PREPASS_WORLD || defined REFL_PREPASS_MIRROR) && !defined REFL_PREPASS
	vec4 ReflLoad(int which, ivec2 c) {
		#ifdef REFL_PREPASS_MIRROR
			if (which == 1) return imageLoad(reflMirror_img, c);
		#endif
		#ifdef REFL_BLUR_AVAILABLE
			if (which == 2) return imageLoad(reflWorldBlur_img, c);
		#endif
		#ifdef REFL_PREPASS_WORLD
			return imageLoad(reflWorld_img, c);
		#else
			return vec4(0.0);
		#endif
	}

	// Averages the reduced-resolution reflection over a grid of taps. REFLECTION_BLUR fixes the widest grid and the
	// surface's own roughness decides how much of it applies: a mirror keeps one tap and pays nothing, a rough
	// surface takes the whole grid and so sees a mixture of what its reflection cone really covers instead of a
	// mirror image of one point. The weight falls off with distance, so the average stays anchored on the exact
	// ray's hit, and taps whose depth is not this surface are skipped, so no blur can cross a silhouette.
	// which: 0 = the traced block reflection, 1 = water/glass, 2 = the blurred block reflection.
	vec4 ReflUpsample(int which, float scale, sampler2D depthTex, float refDepth, float roughness, vec3 refDir) {
		// 1 keeps the small fixed 2 x 2 water/glass always had (it carries a ray, not a roughness); 2 reads an image
		// that a wide blur has already averaged, so it only needs enough taps to interpolate it.
		int side = (which == 1 || which == 2) ? 2 : REFL_BLUR_SIDE;
		float sigma = which == 1 ? 1.5 : which == 2 ? 0.6 : max(clamp(roughness, 0.0, 1.0) * float(REFL_BLUR_SIDE - 1) * 0.5, 1e-3);
		float sigma2 = sigma * sigma;
		vec2 screen = vec2(viewWidth, viewHeight);
		ivec2 loMax = ivec2(ceil(screen * scale)) - 1;
		vec2 lo = gl_FragCoord.xy * scale - 0.5;
		ivec2 loBase = ivec2(floor(lo));
		int halfSpan = (side - 1) / 2;
		float refL = ld(refDepth);

		vec4 sum = vec4(0.0);
		float weightSum = 0.0;
		for (int i = 0; i < 25; i++) {
			if (i >= side * side) break;
			ivec2 o = ivec2(i % side, i / side) - halfSpan;
			// Whole ring at a time: it is skipped once even its nearest possible tap is negligible.
			float ring = float(max(abs(o.x), abs(o.y)));
			if (ring > 1.0 && (ring - 1.0) * (ring - 1.0) > 6.5 * sigma2) continue;
			// Measured from the texel that contains the pixel, so a sharp surface keeps one full-weight tap instead
			// of spreading its weight over taps that all sit a fraction of a texel away.
			vec2 d = vec2(o);
			ivec2 c = clamp(loBase + o, ivec2(0), loMax);
			vec4 v = ReflLoad(which, c);
			if (v.a < 0.0) continue;
			ivec2 rep = min(ivec2((vec2(c) + 0.5) / scale), ivec2(screen) - 1);
			if (abs(ld(texelFetch2D(depthTex, rep, 0).x) - refL) > refL * 0.05 + 1e-4) continue;
			float w = exp(-dot(d, d) / sigma2);
			sum += v * w;
			weightSum += w;
		}
		return weightSum > 0.0 ? sum / weightSum : vec4(0.0, 0.0, 0.0, -1.0);
	}
#endif

#ifndef REFL_PREPASS
void main() {

		vec3 DEBUG = vec3(1.0);

	////// --------------- SETUP STUFF --------------- //////
		vec2 texcoord = (gl_FragCoord.xy*texelSize);
	
		float noise_2 = R2_dither();
		vec2 bnoise = blueNoise(gl_FragCoord.xy).rg;

		#ifdef TAA
			int seed = (frameCounter*5)%40000;
		#else
			int seed = 600;
		#endif

		vec2 r2_sequence = R2_samples(seed).xy;
		vec2 BN = fract(r2_sequence + bnoise);
		float noise = BN.y;


		// float z0 = texture2D(depthtex0,texcoord).x;
		// float z = texture2D(depthtex1,texcoord).x;
		
		float z0 = texelFetch2D(depthtex0, ivec2(gl_FragCoord.xy), 0).x;
		float z =  texelFetch2D(depthtex1, ivec2(gl_FragCoord.xy), 0).x;
		float swappedDepth = z;

		bool isDHrange = z >= 1.0;

		#ifdef DISTANT_HORIZONS
			float DH_mixedLinearZ = sqrt(texture2D(colortex12,texcoord).a/65000.0);
			float DH_depth0 = texture2D(dhDepthTex,texcoord).x;
			float DH_depth1 = texture2D(dhDepthTex1,texcoord).x;

			float depthOpaque = z;
			float depthOpaqueL = linearizeDepthFast(depthOpaque, near, farPlane);
			
			#ifdef DISTANT_HORIZONS
			    float dhDepthOpaque = DH_depth1;
			    float dhDepthOpaqueL = linearizeDepthFast(dhDepthOpaque, dhNearPlane, dhFarPlane);

				if (depthOpaque >= 1.0 || (dhDepthOpaqueL < depthOpaqueL && dhDepthOpaque > 0.0)){
			        depthOpaque = dhDepthOpaque;
			        depthOpaqueL = dhDepthOpaqueL;
			    }
			#endif

			swappedDepth = depthOpaque;
		#else
			float DH_depth0 = 0.0;
			float DH_depth1 = 0.0;
		#endif

	////// --------------- UNPACK OPAQUE GBUFFERS --------------- //////
	
		vec4 data = texelFetch2D(colortex1, ivec2(gl_FragCoord.xy), 0);

		vec3 skyboxCol = data.rgb;

		vec4 dataUnpacked0 = vec4(decodeVec2(data.x),decodeVec2(data.y)); // albedo, masks
		vec4 dataUnpacked1 = vec4(decodeVec2(data.z),decodeVec2(data.w)); // normals, lightmaps
		// vec4 dataUnpacked2 = vec4(decodeVec2(data.z),decodeVec2(data.w));

		vec3 albedo = toLinear(vec3(dataUnpacked0.xz,dataUnpacked1.x));
		vec3 normal = decode(dataUnpacked0.yw);
		vec2 lightmap = dataUnpacked1.yz;

		lightmap.xy = min(max(lightmap.xy - 0.05,0.0)*1.06,1.0); // small offset to hide flickering from precision error in the encoding/decoding on values close to 1.0 or 0.0
		
		#if !defined OVERWORLD_SHADER
			lightmap.y = 1.0;
		#endif

	////// --------------- UNPACK MISC --------------- //////
	
		vec4 SpecularTex = texelFetch2D(colortex8, ivec2(gl_FragCoord.xy), 0);
		float LabSSS = clamp((-65.0 + SpecularTex.z * 255.0) / 190.0 ,0.0,1.0);	
		// LabSSS = 1;

		vec4 normalAndAO = texture2D(colortex15,texcoord);
		vec3 FlatNormals = normalize(normalAndAO.rgb * 2.0 - 1.0);
		vec3 slopednormal = normal;

		float vanilla_AO = z < 1.0 ? clamp(normalAndAO.a,0,1) : 0.0;
		normalAndAO.a = clamp(pow(normalAndAO.a*5,4),0,1);

		if(isDHrange){
			FlatNormals = normal;
			slopednormal = normal;
		}


	////// --------------- MASKS/BOOLEANS --------------- //////
		// 1.0-0.8 ???
		// 0.75 = hand mask
		// 0.60 = grass mask
		// 0.55 = leaf mask (for ssao-sss)
		// 0.50 = lightning bolt mask
		// 0.45 = entity mask
		float opaqueMasks = dataUnpacked1.w;
		// 1.0 = water mask
		// 0.9 = entity mask
		// 0.8 = reflective entities
		// 0.7 = reflective blocks
  		float translucentMasks = texture2D(colortex7, texcoord).a;

		bool isWater = translucentMasks > 0.99;
		// bool isReflectiveEntity = abs(translucentMasks - 0.8) < 0.01;
		// bool isReflective = abs(translucentMasks - 0.7) < 0.01 || isWater || isReflectiveEntity;
		// bool isEntity = abs(translucentMasks - 0.9) < 0.01 || isReflectiveEntity;

		bool lightningBolt = abs(opaqueMasks-0.5) <0.01;
		bool isLeaf = abs(opaqueMasks-0.55) <0.01;
		bool entities = abs(opaqueMasks-0.45) < 0.01;	
		bool isGrass = abs(opaqueMasks-0.60) < 0.01;
		bool hand = abs(opaqueMasks-0.75) < 0.01 && z < 1.0;
		// bool handwater = abs(translucentMasks-0.3) < 0.01 ;
		// bool blocklights = abs(opaqueMasks-0.8) <0.01;

		if(hand){
			convertHandDepth(z);
			convertHandDepth(z0);
		}

		#ifdef DISTANT_HORIZONS
			vec3 viewPos = toScreenSpace_DH(texcoord/RENDER_SCALE - TAA_Offset*texelSize*0.5, z, DH_depth1);
		#else
			vec3 viewPos = toScreenSpace(vec3(texcoord/RENDER_SCALE - TAA_Offset*texelSize*0.5, z));
		#endif
		
		vec3 feetPlayerPos = mat3(gbufferModelViewInverse) * viewPos;
		vec3 feetPlayerPos_normalized = normalize(feetPlayerPos);

		#ifdef POM
			#ifdef Horrible_slope_normals
    			vec3 ApproximatedFlatNormal = normalize(cross(dFdx(feetPlayerPos), dFdy(feetPlayerPos))); // it uses depth that has POM written to it.
				slopednormal = normalize(clamp(normal, ApproximatedFlatNormal*2.0 - 1.0, ApproximatedFlatNormal*2.0 + 1.0) );
			#endif
		#endif
	////// --------------- COLORS --------------- //////

		vec3 waterEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
		vec3 dirtEpsilon = vec3(Dirt_Absorb_R, Dirt_Absorb_G, Dirt_Absorb_B);
		vec3 totEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
		vec3 scatterCoef = Dirt_Amount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / 3.14;

		vec3 Absorbtion = vec3(1.0);
		vec3 AmbientLightColor = vec3(0.0);
		vec3 MinimumLightColor = vec3(1.0);
		vec3 Indirect_lighting = vec3(0.0);
		vec3 Indirect_SSS = vec3(0.0);
		vec2 SSAO_SSS = vec2(1.0);
		
		vec3 DirectLightColor = vec3(0.0);
		vec3 Direct_lighting = vec3(0.0);
		vec3 Direct_SSS = vec3(0.0);
		float cloudShadow = 1.0;
		float Shadows = 1.0;

		vec3 shadowColor = vec3(1.0);
		vec3 SSSColor = vec3(1.0);
		vec3 filteredShadow = vec3(Min_Shadow_Filter_Radius,1.0,0.0);

		float NdotL = 1.0;
		float lightLeakFix = clamp(pow(eyeBrightnessSmooth.y/240. + lightmap.y,2.0) ,0.0,1.0);

		#ifdef OVERWORLD_SHADER
			DirectLightColor = lightCol.rgb / 2400.0;
			AmbientLightColor = averageSkyCol_Clouds / 900.0;
			
			#ifdef USE_CUSTOM_DIFFUSE_LIGHTING_COLORS
				DirectLightColor.rgb = luma(DirectLightColor.rgb) * vec3(DIRECTLIGHT_DIFFUSE_R,DIRECTLIGHT_DIFFUSE_G,DIRECTLIGHT_DIFFUSE_B);
				AmbientLightColor = luma(AmbientLightColor) * vec3(INDIRECTLIGHT_DIFFUSE_R,INDIRECTLIGHT_DIFFUSE_G,INDIRECTLIGHT_DIFFUSE_B);
			#endif
			
			shadowColor = DirectLightColor;

			bool inShadowmapBounds = false;
		#endif

		MinimumLightColor = MinimumLightColor + 0.7 * MinimumLightColor * dot(slopednormal, feetPlayerPos_normalized);

	////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////	UNDER WATER SHADING		////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////


 	if ((isEyeInWater == 0 && isWater) || (isEyeInWater == 1 && !isWater)){
		
		feetPlayerPos += gbufferModelViewInverse[3].xyz;
		
		#ifdef DISTANT_HORIZONS
			vec3 playerPos0 = mat3(gbufferModelViewInverse) *  toScreenSpace_DH(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5, z0, DH_depth0) + gbufferModelViewInverse[3].xyz;
		#else
			vec3 playerPos0 = mat3(gbufferModelViewInverse) * toScreenSpace(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5,z0)) + gbufferModelViewInverse[3].xyz;
		#endif

		float Vdiff = distance(feetPlayerPos, playerPos0);
		float estimatedDepth = Vdiff * abs(feetPlayerPos_normalized.y);// assuming water plane

		// force the absorbance to start way closer to the water surface in low light areas, so the water is visible in caves and such.
		#if MINIMUM_WATER_ABSORBANCE > -1
			float minimumAbsorbance = MINIMUM_WATER_ABSORBANCE*0.1;
		#else
			float minimumAbsorbance	= (1.0 - lightLeakFix);
		#endif
		
		Absorbtion = exp(-totEpsilon * max(Vdiff, minimumAbsorbance));

		// things to note about sunlight in water
		// sunlight gets absorbed by water on the way down to the floor, and on the way back up to your eye. im gonna ingore the latter part lol
		// based on the angle of the sun, sunlight will travel through more/less water to reach the same spot. scale absorbtion depth accordingly
		vec3 sunlightAbsorbtion = exp(-totEpsilon * (estimatedDepth/abs(WsunVec.y)));

		if (isEyeInWater == 1){
			estimatedDepth = 1.0;

			// viewerWaterDepth = max(0.9-lightmap.y,0.0)*3.0;
	  		float distanceFromWaterSurface = max(-(feetPlayerPos.y + (cameraPosition.y - waterEnteredAltitude)),0.0) ;

			Absorbtion = exp(-totEpsilon * distanceFromWaterSurface);
			
			sunlightAbsorbtion = exp(-totEpsilon * (distanceFromWaterSurface/abs(WsunVec.y)));
		}
		
		DirectLightColor *= sunlightAbsorbtion;

		if( nightVision > 0.0 ) Absorbtion += exp(-totEpsilon * 25.0) * nightVision;

		// apply caustics to the lighting, and make sure they dont look weird
		DirectLightColor *= pow(mix(1.0, waterCaustics(feetPlayerPos + cameraPosition, WsunVec)*WATER_CAUSTICS_BRIGHTNESS, clamp(estimatedDepth,0,1)), WATER_CAUSTICS_POWER);
	}


	if (swappedDepth < 1.0) {

		// idk why this do
		feetPlayerPos += gbufferModelViewInverse[3].xyz;
	////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////	    FILTER STUFF      //////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////

		#if defined DISTANT_HORIZONS && defined DH_AMBIENT_OCCLUSION
			doEdgeAwareBlur(colortex3,	colortex14, colortex12, DH_mixedLinearZ, hand, SSAO_SSS, filteredShadow);
		#else
			doEdgeAwareBlur(colortex3,	colortex14, depthtex0, ld(z0), 	hand, SSAO_SSS, filteredShadow);
		#endif
		
		float ShadowBlockerDepth = filteredShadow.y;

	////////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	MAJOR LIGHTSOURCE STUFF 	////////////////////////
	////////////////////////////////////////////////////////////////////////////////////
	
	#ifdef OVERWORLD_SHADER

		float LM_shadowMapFallback =  clamp(lightmap.y, 0.0,1.0);

		float LightningPhase = 0.0;
		vec3 LightningFlashLighting = Iris_Lightningflash(feetPlayerPos, lightningBoltPosition.xyz, slopednormal, LightningPhase) * pow(lightmap.y,10);

		NdotL = clamp((-15 + dot(slopednormal, WsunVec)*255.0) / 240.0  ,0.0,1.0);

		// NdotL = 1;
		float flatNormNdotL = clamp((-15 + dot((FlatNormals), WsunVec)*255.0) / 240.0  ,0.0,1.0);
		
	////////////////////////////////	SHADOWMAP		////////////////////////////////
		// setup shadow projection
		float shadowMapFalloff = smoothstep(0.0, 1.0, min(max(1.0 - length(feetPlayerPos) / (shadowDistance+32.0),0.0)*5.0,1.0));
		float shadowMapFalloff2 = smoothstep(0.0, 1.0, min(max(1.0 - length(feetPlayerPos) / shadowDistance,0.0)*5.0,1.0));

		if(isEyeInWater == 1){
			shadowMapFalloff = 1.0;
			shadowMapFalloff2 = 1.0;
		}
		
		vec3 shadowPlayerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
		
		#if LIGHTLEAKFIX_MODE == 1
			if(!hand) GriAndEminShadowFix(shadowPlayerPos, FlatNormals, lightLeakFix);
		#endif

		vec3 projectedShadowPosition = mat3(shadowModelView) * shadowPlayerPos + shadowModelView[3].xyz;

		applyShadowBias(projectedShadowPosition, shadowPlayerPos, FlatNormals);

		projectedShadowPosition = diagonal3_old(shadowProjection) * projectedShadowPosition + shadowProjection[3].xyz;

		// Calclulate distortion factor before bias application
		#ifdef DISTORT_SHADOWMAP
			float distortFactor = calcDistort(projectedShadowPosition.xy);
			projectedShadowPosition.xy *= distortFactor;
		#else
			float distortFactor = 1.0;
		#endif
		
		projectedShadowPosition.z += shadowProjection[3].z * 0.0012;
		projectedShadowPosition = projectedShadowPosition * vec3(0.5,0.5,0.5/6.0) + vec3(0.5,0.5,0.5) ;

		float ShadowAlpha = 0.0; // this is for subsurface scattering later.
		vec3 tintedSunlight = DirectLightColor; // this is for subsurface scattering later.
		
		shadowColor = ComputeShadowMap_COLOR(projectedShadowPosition, distortFactor, noise_2, filteredShadow.x, flatNormNdotL, shadowMapFalloff, DirectLightColor, ShadowAlpha, tintedSunlight, LabSSS > 0.0,Shadows);
		
		// transition to fallback lightmap shadow mask.
		// shadowColor *= mix(isWater ? lightLeakFix : LM_shadowMapFallback, 1.0, shadowMapFalloff2);

		#if LIGHTLEAKFIX_MODE == 2
			if(isEyeInWater != 1) shadowColor *= lightLeakFix; // light leak fix
		#endif
		
	////////////////////////////////	SUN SSS		////////////////////////////////
		#if SSS_TYPE != 0

			float sunSSS_density = LabSSS;
			float SSS_shadow = ShadowAlpha;
			
			#ifdef DISTANT_HORIZONS
				shadowMapFalloff2 = smoothstep(0.0, 1.0, min(max(1.0 - length(feetPlayerPos) / min(shadowDistance, max(far-32.0,32.0)),0.0)*5.0,1.0));
			#endif

			#ifndef RENDER_ENTITY_SHADOWS
				if(entities) sunSSS_density = 0.0;
			#endif
			
			#ifdef SCREENSPACE_CONTACT_SHADOWS
				vec2 SS_directLight = SSRT_Shadows(toScreenSpace_DH(texcoord/RENDER_SCALE, z, DH_depth1), isDHrange, normalize(WsunVec*mat3(gbufferModelViewInverse)), interleaved_gradientNoise_temporal(), sunSSS_density > 0.0 && shadowMapFalloff2 < 1.0, hand);
				// combine shadowmap with screenspace shadows.
				shadowColor *= SS_directLight.r;
			#else
				vec2 SS_directLight = vec2(1,0);
				ShadowBlockerDepth = max(ShadowBlockerDepth, (1.0-shadowMapFalloff2) * 10.0);
			#endif
			
				
			#ifdef TRANSLUCENT_COLORED_SHADOWS
				SSSColor = tintedSunlight;
			#else
				SSSColor = DirectLightColor;
			#endif

			SSSColor = SubsurfaceScattering_sun(albedo, ShadowBlockerDepth, sunSSS_density, clamp(dot(feetPlayerPos_normalized, WsunVec),0.0,1.0), SS_directLight.g, shadowMapFalloff2, hand);
			
			if(isEyeInWater != 1) SSSColor *= lightLeakFix;
			
			float cloudShadows = GetCloudShadow(feetPlayerPos.xyz + cameraPosition, WsunVec);
			shadowColor *= cloudShadows;
			SSSColor *= cloudShadow*cloudShadows;

		#endif
	#endif

	#ifdef END_SHADER

		#ifdef END_LIGHTNING
			float vortexBounds = clamp(vortexBoundRange - length(feetPlayerPos+cameraPosition), 0.0,1.0);
		#else
			float vortexBounds = 1.0;
		#endif
		
        vec3 lightPos = LightSourcePosition(feetPlayerPos+cameraPosition, cameraPosition,vortexBounds);

		float lightningflash = texelFetch2D(colortex4,ivec2(1,1),0).x/150.0;
		vec3 lightColors = LightSourceColors(vortexBounds, lightningflash);
		
		float end_NdotL = clamp(dot(slopednormal, normalize(-lightPos))*0.5+0.5,0.0,1.0);
		end_NdotL *= end_NdotL;

		float fogShadow = GetEndFogShadow(feetPlayerPos+cameraPosition, lightPos);
		float endPhase = endFogPhase(lightPos);

		Direct_lighting += lightColors * endPhase * end_NdotL * fogShadow;
	#endif
	

	/////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	INDIRECT LIGHTING 	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////////////

		#if defined OVERWORLD_SHADER
			float skylight = 1.0;
		
			#if indirect_effect == 0 || indirect_effect == 1 || indirect_effect == 2

				vec3 indirectNormal = slopednormal / dot(abs(slopednormal),vec3(1.0));

				float SkylightDir = indirectNormal.y;

				if(isGrass) SkylightDir = 1.0;
				SkylightDir = clamp(SkylightDir*0.7+0.3, 0.0, pow(1-pow(1-SSAO_SSS.x, 0.5),4.0) * 0.7 + 0.3);

				skylight = mix(0.2 + 2.3*(1.0-lightmap.y), 2.5, SkylightDir)/2.5;

				// skylight = 1.0;
			#endif

			#if indirect_effect == 3 || indirect_effect == 4
				skylight = 1.0;
			#endif
			
			Indirect_lighting += doIndirectLighting(AmbientLightColor * skylight, MinimumLightColor, lightmap.y);

		#endif

		#ifdef NETHER_SHADER
			Indirect_lighting = volumetricsFromTex(normalize(normal), colortex4, 6).rgb / 1200.0;
			vec3 up = volumetricsFromTex(vec3(0.0,1.0,0.0), colortex4, 6).rgb / 1200.0;
			
			#if indirect_effect == 1
				Indirect_lighting = mix(up, Indirect_lighting,  clamp(pow(1.0-pow(1.0-SSAO_SSS.x, 0.5),2.0),0.0,1.0));
			#endif
			
			AmbientLightColor = Indirect_lighting;
		#endif
		
		#ifdef END_SHADER
			Indirect_lighting = vec3(0.3,0.6,1.0);
			
			Indirect_lighting = Indirect_lighting + 0.7*mix(-Indirect_lighting, Indirect_lighting * dot(slopednormal, feetPlayerPos_normalized), clamp(pow(1.0-pow(1.0-SSAO_SSS.x, 0.5),2.0),0.0,1.0));
			Indirect_lighting *= 0.1;

			Indirect_lighting += lightColors * (endPhase*endPhase) * (1.0-exp(vec3(0.6,2.0,2.0) * -(endPhase*0.01))) /1000.0;
		#endif
		
		#ifdef IS_LPV_ENABLED
			vec3 normalOffset = vec3(0.0);

			if (any(greaterThan(abs(FlatNormals), vec3(1.0e-6))))
				normalOffset = 0.5*(FlatNormals);

			#if LPV_NORMAL_STRENGTH > 0
				vec3 texNormalOffset = -normalOffset + slopednormal;
				normalOffset = mix(normalOffset, texNormalOffset, (LPV_NORMAL_STRENGTH*0.01));
			#endif

			vec3 lpvPos = GetLpvPosition(feetPlayerPos) + normalOffset;
		#else
			const vec3 lpvPos = vec3(0.0);
		#endif

		vec3 blockLightColor = doBlockLightLighting( vec3(TORCH_R,TORCH_G,TORCH_B), lightmap.x, feetPlayerPos, lpvPos);

		// ACT replaces Bliss' block light inside its volume, as upstream does: the
		// vanilla lightmap sets brightness, the floodfilled volume sets colour.
		#if COLORED_LIGHTING_INTERNAL > 0
			{
				vec3 actVoxelPos = SceneToVoxel(feetPlayerPos) + FlatNormals * 0.55;
				if (CheckInsideVoxelVolume(actVoxelPos)) {
					vec4 actVolume = sqrt(max(GetLightVolume(clamp01(actVoxelPos / vec3(voxelVolumeSize))), vec4(0.0)));
					// Upstream: volume alpha is extra light for dim sources (candles) -- more saturated colour and a raised lightmap.
					vec3 actLight = actVolume.rgb * (1.0 + 50.0 * actVolume.a);
					vec3 actColor = DoLuminanceCorrection(actLight + vec3(TORCH_R,TORCH_G,TORCH_B) * 0.05);

					#if COLORED_LIGHT_SATURATION != 100
						actColor = mix(vec3(GetLuminance(actColor)), actColor, COLORED_LIGHT_SATURATION * 0.01);
					#endif

					float actLum = GetLuminance(blockLightColor);
					if (actVolume.a > 0.0) {
						// Upstream mixes its lightmap curve toward 10 (~level 11); invert its low-light part to a lightmap for Bliss' curve.
						float actLx = clamp(lightmap.x, 0.0, 1.0);
						float actCompXM = pow(3.5 * pow(actLx, 8.0) + 2.1 * actLx, 2.25);
						float actLxBoost = min(pow(mix(actCompXM, 10.0, actVolume.a), 1.0 / 2.25) / 2.1, 0.76);
						if (actLxBoost > actLx) actLum = max(actLum, GetLuminance(doBlockLightLighting(vec3(TORCH_R,TORCH_G,TORCH_B), actLxBoost, feetPlayerPos, lpvPos)));
					}

					vec3 actBlockLight = actLum * actColor * (COLORED_LIGHT_STRENGTH / 1300.0);

					vec3 actAbsPos = abs(feetPlayerPos);
					actAbsPos.y *= 2.0;
					float actFade = min(max(actAbsPos.x, max(actAbsPos.y, actAbsPos.z)) / effectiveACTdistance * 2.0, 1.0);
					blockLightColor = mix(actBlockLight, blockLightColor, actFade * actFade);
				}
			}
		#endif

		Indirect_lighting += blockLightColor;

		vec4 flashLightSpecularData = vec4(0.0);
		#ifdef FLASHLIGHT
			vec3 newViewPos = viewPos;


			float flashlightshadows = SSRT_FlashLight_Shadows(toScreenSpace_DH(texcoord/RENDER_SCALE, z, DH_depth1), isDHrange, newViewPos, interleaved_gradientNoise_temporal());
			
			
			Indirect_lighting += calculateFlashlight(texcoord, viewPos, albedoSmooth, slopednormal, flashLightSpecularData, hand);
		#endif

	/////////////////////////////////////////////////////////////////////////////////////
	/////////////////////////////	EFFECTS FOR INDIRECT	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////////////////

		float SkySSS = 1.0;
		SkySSS = SSAO_SSS.y;
		
		vec3 AO = vec3(1.0);

		#if indirect_effect == 0
			AO = vec3(pow(1.0 - vanilla_AO*vanilla_AO,5.0));
			Indirect_lighting *= AO;
		#endif

		#if indirect_effect == 1

			float vanillaAO_curve = pow(1.0 - vanilla_AO*vanilla_AO,5.0);
			float SSAO_curve = pow(SSAO_SSS.x,4.0);

			// use the min of vanilla ao so they dont overdarken eachother
			// AO = vec3( min(vanillaAO_curve, SSAO_curve) );
			AO = vec3( SSAO_curve );
			Indirect_lighting *= AO;
		#endif

		// // GTAO... this is so dumb but whatevverrr
		#if indirect_effect == 2
			float vanillaAO_curve = pow(1.0 - vanilla_AO*vanilla_AO,5.0);

			vec2 r2 = fract(R2_samples((frameCounter%40000) + frameCounter*2) + bnoise);
			float GTAO =  !hand ? ambient_occlusion(vec3(texcoord/RENDER_SCALE-TAA_Offset*texelSize*0.5, z), viewPos, worldToView(slopednormal), r2) : 1.0;
			
			AO = vec3(min(vanillaAO_curve,GTAO));
			
			Indirect_lighting *= AO;
		#endif

		// RTAO and/or SSGI
		#if indirect_effect == 3 || indirect_effect == 4
			if(!hand) Indirect_lighting = ApplySSRT(Indirect_lighting, blockLightColor, MinimumLightColor, viewPos, normal, vec3(bnoise, noise_2), lightmap.y, isGrass, isDHrange);
		#endif



	////////////////////////////////////////////////////////////////////////////////
	/////////////////////////	SUB SURFACE SCATTERING	////////////////////////////
	////////////////////////////////////////////////////////////////////////////////
	
	/////////////////////////////	SKY SSS		/////////////////////////////
		#if defined Ambient_SSS && defined OVERWORLD_SHADER // && indirect_effect == 1
			vec3 ambientColor = AmbientLightColor * ambientsss_brightness * ambient_brightness * 2.0;
			

			Indirect_SSS = SubsurfaceScattering_sky(albedo, SkySSS, LabSSS);
			Indirect_SSS *= lightmap.y;

			float thingy = SkySSS;
			thingy = pow(thingy,3.5);
			thingy = 1-pow(1-thingy,5);

			Indirect_lighting = Indirect_lighting + Indirect_SSS * ambientColor;

			// float lightmapCurve =  ((pow(lightmap.y,15.0)*2.0 + lightmap.y*lightmap.y)/3.0);
			// Indirect_lighting = ambient_brightness * AmbientLightColor * mix(Indirect_SSS*lightmap.y*2.5, vec3(1.0), skylight * SSAO_curve * lightmapCurve);
			// Indirect_lighting += blockLightColor * SSAO_curve;

			// #ifdef OVERWORLD_SHADER
			// 	if(LabSSS > 0.0) Indirect_lighting += (1.0-SkySSS) * LightningPhase * lightningEffect *  pow(lightmap.y,10);
			// #endif
		#endif
	
	/////////////////////////////////////////////////////////////////////////
	/////////////////////////////	FINALIZE	/////////////////////////////
	/////////////////////////////////////////////////////////////////////////


		// shadowColor *= 0.0;
		// SSSColor *= 0.0;

		#ifdef SSS_view
			albedo = vec3(1);
			NdotL = 0;
		#endif
		#if defined END_SHADER
			Direct_lighting *= AO;
		#endif
		#ifdef OVERWORLD_SHADER
			// mix(SSS, 1, t) drops below t once the coloured shadow term exceeds 1, darkening sunlit SSS blocks; SSS only fills the unlit part.
			#ifdef AO_in_sunlight
				// Direct_lighting = shadowColor*NdotL*(AO*0.7+0.3) + SSSColor * (1.0-NdotL);
				vec3 directLit = NdotL*shadowColor * (AO*0.7+0.3);
			#else
				// Direct_lighting = shadowColor*NdotL + SSSColor * (1.0-NdotL);
				vec3 directLit = NdotL*shadowColor;
			#endif
			Direct_lighting = DirectLightColor * (directLit + SSSColor * max(1.0 - directLit, 0.0));
		#endif

		#if defined OVERWORLD_SHADER && defined DEFERRED_SPECULAR
			#ifdef IPBR
				// le perfecto bliss: hand the puddle system the values a pack-less
				// LabPBR setup would produce, not IPBR's.
				//
				// applyPuddles was written against LabPBR inputs.  It mixes the
				// smoothness toward 1.0 -- a perfect mirror -- and gates its
				// wet-darkening on `f0 < 229.5/255.0`.  Fed IPBR's specular it
				// made wet ground a near-black mirror: mirror-smooth from the
				// first, albedo pushed down by the second, and at a shallow angle
				// reflecting mostly dark ground rather than sky.
				//
				// Smoothness 1 with f0 0 is what Bliss' own path produces without
				// a resource pack, so the puddle shader now runs exactly as
				// upstream intends.  IPBR's real specular values still drive the
				// reflections; they just no longer steer the wetness model.
				float puddleSmoothness = 1.0;
				float puddleF0 = 0.0;
				if(!hand && !entities) applyPuddles(feetPlayerPos + cameraPosition, FlatNormals, lightmap.y, isWater, albedo, normal, puddleSmoothness, puddleF0);
			#else
				if(!hand && !entities) applyPuddles(feetPlayerPos + cameraPosition, FlatNormals, lightmap.y, isWater, albedo, normal, SpecularTex.r, SpecularTex.g);
			#endif
		#endif

		#if NORMAL_AMBIENT_RELIEF > 0
			// Texels tilted up see more of the sky, tilted down less: keeps normal detail visible without sun.
			if (!hand) Indirect_lighting *= clamp(1.0 + (normal.y - FlatNormals.y) * NORMAL_AMBIENT_RELIEF * 0.01, 0.25, 2.0);
		#endif

		vec3 FINAL_COLOR = (Indirect_lighting + Direct_lighting) * albedo;

		Emission(FINAL_COLOR, albedo, SpecularTex.a);
		
		if(lightningBolt) FINAL_COLOR = vec3(77.0, 153.0, 255.0);
		
		#if defined DEFERRED_SPECULAR	
			vec3 specularNoises = vec3(BN.xy, blueNoise());
    		vec3 specularNormal = normal;
			// le perfecto bliss: the sign test must use the GEOMETRIC normal.
			// Using the shaded one makes this selection flip per fragment wherever
			// the perturbed normal crosses perpendicular to the view -- and since
			// feetPlayerPos_normalized varies per fragment, that happens in a
			// texture-locked pattern even when the normal itself is constant.
			// The result is a hard binary mesh across the surface: view-dependent,
			// indifferent to the light source, and immune to the perturbation's
			// magnitude.  FlatNormals gives the same intent with a test that is
			// stable across a face.
			if (dot(FlatNormals, (feetPlayerPos_normalized)) > 0.0) specularNormal = FlatNormals;

			#ifdef INCLUDE_BLISS_WSR
					wsrLodScale = float(REFLECTION_RES_WORLD) * 0.01;
				wsrSunColor = DirectLightColor;
				wsrAmbientColor = AmbientLightColor;
				wsrSunDir = WsunVec;
				#ifdef OVERWORLD_SHADER
					wsrDayFactor = clamp((unsigned_WsunVec.y + 0.05) / 0.15, 0.0, 1.0);
				#endif
			#endif
			
			// Terrain seen through water or glass already gets that surface's own reflection; tracing its own stacked a second SSR/WSR per pixel (upstream skips it too).
			specBehindTranslucent = z0 < z && !hand && texelFetch2D(colortex2, ivec2(gl_FragCoord.xy), 0).a > 0.0;
			#ifdef REFL_PREPASS_WORLD
				// A reduced-resolution trace carries position but not roughness: one ray per reduced texel cannot
				// spread over a cone the way one ray per screen pixel does. Rough surfaces therefore read the
				// blurred copy of the same buffer, which is the same rays averaged over the cone they really see.
				float reflRough = clamp((1.0 - SpecularTex.r) * 2.0, 0.0, 1.0);
				float reflScale = float(REFLECTION_RES_WORLD) * 0.01;
				#ifdef REFL_BLUR_AVAILABLE
					// Mirrors keep the trace (their cone is a ray); a polished surface gets a little of the blur as a
					// broad halo, and anything genuinely rough gets all of it. If the soft copy has nothing for this
					// pixel the trace is used instead, so the blur can only soften a reflection, never remove it.
					float reflBlurMix = smoothstep(0.15, 0.6, reflRough);
					vec4 reflSharp = ReflUpsample(0, reflScale, depthtex1, z, reflRough, vec3(0.0));
					vec4 reflSoft = ReflUpsample(2, reflScale, depthtex1, z, reflRough, vec3(0.0));
					if (reflSoft.a < 0.0) reflSoft = reflSharp;
					reflWorldFetched = mix(reflSharp, reflSoft, reflBlurMix);
				#else
					reflWorldFetched = ReflUpsample(0, reflScale, depthtex1, z, reflRough, vec3(0.0));
				#endif
				reflWorldFetched.a = max(reflWorldFetched.a, 0.0);
			#endif
			FINAL_COLOR = specularReflections(viewPos, feetPlayerPos_normalized, WsunVec, specularNoises, specularNormal, SpecularTex.r, SpecularTex.g, albedo, FINAL_COLOR, DirectLightColor*shadowColor, lightmap.y, hand, flashLightSpecularData);
		#endif

		gl_FragData[0].rgb = FINAL_COLOR;
		#if defined REFL_PREPASS_WORLD && defined DEFERRED_SPECULAR
			// Reflection buffer on its own, so its stability can be judged apart from the highlight.
			if (DEBUG_VIEW == debug_REFL && hideGUI == 0)
				gl_FragData[0].rgb = reflWorldFetched.a < 0.0 ? vec3(0.5) : reflWorldFetched.rgb * 4.0;
		#elif defined REFLECTION_PREPASS_ON && defined OVERWORLD_SHADER && defined INCLUDE_BLISS_WSR
			if (DEBUG_VIEW == debug_REFL && hideGUI == 0) gl_FragData[0].rgb = vec3(1.0, 0.0, 1.0);
		#endif

	}else{
		vec3 Background = vec3(0.0);


		#ifdef OVERWORLD_SHADER

			float atmosphereGround = 1.0 - exp2(-50.0 * pow(clamp(feetPlayerPos_normalized.y+0.025,0.0,1.0),2.0)  ); // darken the ground in the sky.
			
			#if RESOURCEPACK_SKY == 1 || RESOURCEPACK_SKY == 0 || RESOURCEPACK_SKY == 3
				// vec3 orbitstar = vec3(feetPlayerPos_normalized.x,abs(feetPlayerPos_normalized.y),feetPlayerPos_normalized.z); orbitstar.x -= WsunVec.x*0.2;
				vec3 orbitstar = normalize(mat3(gbufferModelViewInverse) * toScreenSpace(vec3(texcoord/RENDER_SCALE,1.0)));
				// float radiance = 2.39996 - (worldTime + worldDay*24000.0) / 24000.0;
				float radiance = 2.39996 ;
				// float radiance = 2.39996 + frameTimeCounter;
				mat2 rotationMatrix  = mat2(vec2(cos(radiance),  -sin(radiance)),  vec2(sin(radiance),  cos(radiance)));
				
				orbitstar.xy *= rotationMatrix;
				
  				#if defined OVERWORLD_SHADER && defined TWILIGHT_FOREST_FLAG
					Background += stars(orbitstar) * 100.0;
  				#else
					Background += stars(orbitstar) * 10.0 * clamp(-unsigned_WsunVec.y*2.0,0.0,1.0);
				#endif

				#if !defined ambientLight_only && (RESOURCEPACK_SKY == 1 || RESOURCEPACK_SKY == 0)
					Background += drawSun(dot(unsigned_WsunVec, feetPlayerPos_normalized), 0, DirectLightColor,vec3(0.0));

					vec3 moonLightCol = moonCol / 2400.0;

					Background += drawMoon(feetPlayerPos_normalized, WmoonVec, moonLightCol, Background); 
					// Background += drawSun(dot(WmoonVec, feetPlayerPos_normalized),0, moonLightCol,vec3(0.0));
				#endif

				Background *= atmosphereGround;
			#endif
			
			#ifndef ISOLATE_RESOURCEPACK_SKY
				vec3 Sky = skyFromTex(feetPlayerPos_normalized, colortex4)/1200.0 * Sky_Brightness;
				Background += Sky;
			#endif
			
			#if RESOURCEPACK_SKY == 1 || RESOURCEPACK_SKY == 2 || RESOURCEPACK_SKY == 3
				vec3 resourcePackskyBox = skyboxCol * 50.0 * clamp(unsigned_WsunVec.y*255.0,0.1,1.0);

				#if defined SKY_GROUND && !defined ISOLATE_RESOURCEPACK_SKY
					resourcePackskyBox *= atmosphereGround;
				#endif

				Background += resourcePackskyBox;
			#endif

		#endif

		gl_FragData[0].rgb = clamp(fp10Dither(Background, triangularize(noise_2)), 0.0, 65000.);
	}


	if(translucentMasks > 0.0 ){
		// water absorbtion will impact ALL light coming up from terrain underwater.
		gl_FragData[0].rgb *= Absorbtion;

		#ifdef DISTANT_HORIZONS
	  		float DH_mixedLinearZ = sqrt(texelFetch2D(colortex12,ivec2(gl_FragCoord.xy),0).a/65000.0);
			vec4 vlBehingTranslucents = BilateralUpscale_VLFOG(colortex13, colortex12, DH_mixedLinearZ);
		#else
			vec4 vlBehingTranslucents = BilateralUpscale_VLFOG(colortex13, depthtex1, ld(z));
		#endif

    	gl_FragData[0].rgb = gl_FragData[0].rgb * vlBehingTranslucents.a + vlBehingTranslucents.rgb;
	}

	// gl_FragData[0].rgb = lightmap.x* vec3(1.0);
	
	////// DEBUG VIEW STUFF
	#if DEBUG_VIEW == debug_SHADOWMAP	
		gl_FragData[0].rgb = vec3(1.0) * (Shadows * NdotL * 0.9 + 0.1);
		
		if(dot(feetPlayerPos_normalized, unsigned_WsunVec) > 0.999 ) gl_FragData[0].rgb = vec3(10,10,0);
		if(dot(feetPlayerPos_normalized, -WmoonVec) > 0.999 ) gl_FragData[0].rgb = vec3(1,1,10);
	#endif
	#if DEBUG_VIEW == debug_NORMALS
		if(swappedDepth >= 1.0) Direct_lighting = vec3(1.0);
		gl_FragData[0].rgb = normal ;
	#endif
	#if DEBUG_VIEW == debug_SPECULAR
		if(swappedDepth >= 1.0) Direct_lighting = vec3(1.0);
		gl_FragData[0].rgb = SpecularTex.rgb;
	#endif
	#if DEBUG_VIEW == debug_INDIRECT
		if(swappedDepth >= 1.0) Direct_lighting = vec3(5.0);
		gl_FragData[0].rgb = Indirect_lighting;
	#endif
	#if DEBUG_VIEW == debug_DIRECT
		if(swappedDepth < 1.0) gl_FragData[0].rgb = Direct_lighting;
	#endif
	#if DEBUG_VIEW == debug_VIEW_POSITION
		gl_FragData[0].rgb = viewPos * 0.001;
	#endif
	// ----------------------------------------------------------------------
	// ACT diagnostic.
	//
	//   red   -- compiled in?  Lit means COLORED_LIGHTING_INTERNAL > 0, i.e.
	//            both ACT_ENABLED and Iris' IRIS_FEATURE_CUSTOM_IMAGES resolved.
	//   green -- inside the voxel volume?  Lit means SceneToVoxel and
	//            CheckInsideVoxelVolume agree the camera is tracked.
	//   blue  -- light in the FLOODFILLED volume at this fragment.
	//
	// Reading it: red+green with no blue (yellow, as first observed) means the
	// volume is positioned correctly but empty -- so the fault is upstream, in
	// the shadow-pass write or the shadowcomp floodfill, and not in the gate,
	// the options or the read.  With hold-GUI the same view shows the RAW block
	// ids instead of the floodfilled light, which separates those two:
	//
	//   raw ids lit, light dark  -> the write works, the floodfill does not
	//   raw ids dark too         -> the write never happens
	// ----------------------------------------------------------------------
	#if DEBUG_VIEW == debug_ACT
		// Gate bitmask, evaluated independently of COLORED_LIGHTING_INTERNAL so it
		// still reports in the branches where the path is compiled out.  Nothing
		// here touches the light volume, so it compiles either way.
		//
		//   red   -- ACT_ENABLED == 1
		//   green -- IRIS_FEATURE_CUSTOM_IMAGES defined (Iris accepted CUSTOM_IMAGES)
		//   blue  -- platform term: not macOS, no Distant Horizons
		//
		// White (1,1,1) is the only combination that lets ACT compile in, so if this
		// view renders anything but white the missing channel names the exact term
		// that failed.
		//
		// This exists because the compile harness CANNOT answer the question:
		// tools/validate.py puts IRIS_FEATURE_CUSTOM_IMAGES in ENGINE_DEFINES
		// unconditionally, so a probe there always reports the flag as defined no
		// matter what the real Iris build does with the macro.
		float actGateR = 0.0;
		float actGateG = 0.0;
		float actGateB = 0.0;
		#if ACT_ENABLED == 1
		actGateR = 1.0;
		#endif
		#ifdef IRIS_FEATURE_CUSTOM_IMAGES
		actGateG = 1.0;
		#endif
		#if !defined MC_OS_MAC && !(defined DH_TERRAIN || defined DH_WATER)
		actGateB = 1.0;
		#endif
		#ifdef COLORED_LIGHTING_INTERNAL
			#if COLORED_LIGHTING_INTERNAL > 0
				vec3 actVoxelPosD = SceneToVoxel(feetPlayerPos) + FlatNormals * 0.55;
				float insideD = CheckInsideVoxelVolume(actVoxelPosD) ? 1.0 : 0.0;

				vec3 lightD = vec3(0.0);
				vec3 rawD = vec3(0.0);
				if (insideD > 0.5) {
					ivec3 vpD = ivec3(clamp01(actVoxelPosD / vec3(voxelVolumeSize)) * vec3(voxelVolumeSize));
					vpD = clamp(vpD, ivec3(0), voxelVolumeSize - 1);

					lightD = sqrt(GetLightVolume(clamp01(actVoxelPosD / vec3(voxelVolumeSize)))).rgb * 4.0;

					uint rawD_ = texelFetch(voxel_sampler, vpD, 0).x & 32767u;
					rawD = vec3(rawD_ > 0u ? 1.0 : 0.0, clamp(float(rawD_) / 255.0, 0.0, 1.0), 0.0);
				}

				if (hideGUI == 1) {
					// raw block ids: red = any id written, green = id value
					gl_FragData[0].rgb = vec3(insideD, rawD.g, rawD.r);
				} else {
					gl_FragData[0].rgb = vec3(1.0, insideD, clamp(length(lightD), 0.0, 1.0));
				}
				Direct_lighting = vec3(0.0);
				Indirect_lighting = vec3(0.0);
			#else
				gl_FragData[0].rgb = vec3(actGateR, actGateG, actGateB);
			#endif
		#else
			gl_FragData[0].rgb = vec3(actGateR, actGateG, actGateB);
		#endif
	#endif
	// GUI shown: normal render, specular tints WSR hits green and misses red. GUI hidden: the voxel scene traced from the camera (dark red = miss).
	#if DEBUG_VIEW == debug_WSR
		#ifdef INCLUDE_BLISS_WSR
			if (hideGUI == 1) {
				vec4 wsrDbg = BlissWSR(gbufferModelViewInverse[3].xyz, feetPlayerPos_normalized, feetPlayerPos_normalized);
				gl_FragData[0].rgb = wsrDbg.a > 0.0 ? wsrDbg.rgb : vec3(0.3, 0.0, 0.0);
			}
		#else
			gl_FragData[0].rgb = vec3(1.0, 0.0, 1.0);
		#endif
	#endif
	#if DEBUG_VIEW == debug_FILTERED_STUFF
		// if(hideGUI == 0){
			float value = SSAO_SSS.y;
			value = pow(value,3.5);
			value = 1-pow(1-value,5);

			if(hideGUI == 1) value = pow(SSAO_SSS.x,6);
			gl_FragData[0].rgb = vec3(value);

			if(swappedDepth >= 1.0) gl_FragData[0].rgb  = vec3(1.0);
		// }
	#endif

	#ifdef WSR_DEFER_RESOLVE
	{
		// Reflection of the front translucent, recorded by the water pass; added to its colour (x0.1 buffer scale).
		vec4 translucentOut = texelFetch2D(colortex2, ivec2(gl_FragCoord.xy), 0);
		if (z0 < 1.0 && translucentOut.a > 0.0) {
			uvec4 td = imageLoad(wsrTrans_img, ivec2(gl_FragCoord.xy));
			if (td.w != 0u && abs(uintBitsToFloat(td.w) - z0) < 1e-6) {
				vec2 baseBW = unpackHalf2x16(td.y);
				vec3 base = vec3(unpackHalf2x16(td.x), baseBW.x);

				#ifdef REFL_PREPASS_MIRROR
					vec4 env = ReflUpsample(1, float(REFLECTION_RES_MIRROR) * 0.01, depthtex0, z0, 0.0, WsrOctDecode(unpackSnorm2x16(td.z)));
				#else
					vec4 env = vec4(0.0, 0.0, 0.0, -1.0);
				#endif
				// No prepass sample covers this pixel (thin edges at low resolution, or no prepass): trace it here.
				if (env.a < 0.0) {
					vec3 rayDir = WsrOctDecode(unpackSnorm2x16(td.z));
					vec3 viewPosS = toScreenSpace(vec3(texcoord/RENDER_SCALE - TAA_Offset*texelSize*0.5, z0));
					vec3 surfPos = mat3(gbufferModelViewInverse) * viewPosS + gbufferModelViewInverse[3].xyz;
					vec3 viewDir = normalize(surfPos - gbufferModelViewInverse[3].xyz);
					vec3 surfNormal = normalize(rayDir - viewDir);

					wsrLodScale = float(REFLECTION_RES_MIRROR) * 0.01;
					wsrSunColor = lightCol.rgb / 2400.0;
					wsrAmbientColor = averageSkyCol_Clouds / 900.0;
					wsrSunDir = WsunVec;
					env = MirrorEnvironment(viewPosS, surfPos, surfNormal, rayDir, baseBW.y < 0.0, blueNoise(vec2(gl_FragCoord.xy)).g, float(FORWARD_SSR_QUALITY));
				}
				translucentOut.rgb += abs(baseBW.y) * env.a * (env.rgb - base) * 0.1;
				#if DEBUG_VIEW == debug_WSR
					translucentOut.rgb = vec3(0.0, 1.0, 0.0) * (0.2 + env.a);
				#endif
			}
			#if DEBUG_VIEW == debug_WSR
				else translucentOut.rgb = td.w != 0u ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
			#endif
		}
		gl_FragData[1] = translucentOut;
	}
	#endif

	#ifdef WSR_DEFER_RESOLVE
		/* RENDERTARGETS:3,2 */
	#else
		/* RENDERTARGETS:3 */
	#endif
}
#else
	#include "/lib/voxelization/reflectionPrepass.glsl"
#endif
