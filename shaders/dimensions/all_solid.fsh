#extension GL_ARB_shader_texture_lod : enable

#include "/lib/settings.glsl"
#include "/lib/blocks.glsl"
#include "/lib/entities.glsl"
#include "/lib/items.glsl"
#include "/lib/ipbr/ipbr_settings.glsl"

flat varying int NameTags;

#ifdef HAND
#undef POM
#endif

// IntegratedPBR+ owns the normal in IPBR mode and has no heightmap to trace,
// so Bliss' parallax occlusion mapping stands down there.
#ifdef IPBR
#undef POM
#endif

#ifndef USE_LUMINANCE_AS_HEIGHTMAP
#ifndef MC_NORMAL_MAP
#undef POM
#endif
#endif

#ifdef POM
#define MC_NORMAL_MAP
#endif


varying float VanillaAO;

const float mincoord = 1.0/4096.0;
const float maxcoord = 1.0-mincoord;

const float MAX_OCCLUSION_DISTANCE = MAX_DIST;
const float MIX_OCCLUSION_DISTANCE = MAX_DIST*0.9;
const int   MAX_OCCLUSION_POINTS   = MAX_ITERATIONS;

uniform vec2 texelSize;
uniform int framemod8;

// #ifdef POM
varying vec4 vtexcoordam; // .st for add, .pq for mul
varying vec4 vtexcoord;

vec2 dcdx = dFdx(vtexcoord.st*vtexcoordam.pq)*exp2(Texture_MipMap_Bias);
vec2 dcdy = dFdy(vtexcoord.st*vtexcoordam.pq)*exp2(Texture_MipMap_Bias);
// #endif

#include "/lib/res_params.glsl"
varying vec4 lmtexcoord;

varying vec4 vColor;

uniform float far;


uniform float wetness;
varying vec4 normalMat;


// FlatNormals is written unconditionally by the vertex stage, so it cannot live
// inside the MC_NORMAL_MAP guard.
varying vec3 FlatNormals;

#if defined MC_NORMAL_MAP || defined IPBR_NEEDS_TANGENT
	varying vec4 tangent;
#endif
#ifdef MC_NORMAL_MAP
	uniform sampler2D normals;
#endif


uniform sampler2D specular;



uniform sampler2D texture;
uniform sampler2D colortex1;//albedo(rgb),material(alpha) RGBA16
uniform float frameTimeCounter;
uniform int frameCounter;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float rainStrength;
uniform sampler2D noisetex;//depth
uniform sampler2D depthtex0;

#if defined VIVECRAFT
	uniform bool vivecraftIsVR;
	uniform vec3 vivecraftRelativeMainHandPos;
	uniform vec3 vivecraftRelativeOffHandPos;
	uniform mat4 vivecraftRelativeMainHandRot;
	uniform mat4 vivecraftRelativeOffHandRot;
#endif

uniform vec4 entityColor;

// in vec3 velocity;

flat varying float blockID;
// Raw Iris block id -- Complementary's integratedPBR+ numbering.
flat varying float irisBlockId;

flat varying float SSSAMOUNT;
flat varying float EMISSIVE;
flat varying int LIGHTNING;
flat varying int PORTAL;
flat varying int SIGN;


flat varying float HELD_ITEM_BRIGHTNESS;
uniform float noPuddleAreas;
uniform float nightVision;

// float interleaved_gradientNoise(){
// 	return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y)+frameTimeCounter*51.9521);
// }

float interleaved_gradientNoise_temporal(){
	#ifdef TAA
		return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887);
	#endif
}
float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}
float R2_dither(){
	vec2 coord = gl_FragCoord.xy ;

	#ifdef TAA
		coord += + (frameCounter%40000) * 2.0;
	#endif
	
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha.x * coord.x + alpha.y * coord.y ) ;
}
float blueNoise(){
	#ifdef TAA
  		return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887);
	#endif
}

mat3 inverseMatrix(mat3 m) {
  float a00 = m[0][0], a01 = m[0][1], a02 = m[0][2];
  float a10 = m[1][0], a11 = m[1][1], a12 = m[1][2];
  float a20 = m[2][0], a21 = m[2][1], a22 = m[2][2];

  float b01 = a22 * a11 - a12 * a21;
  float b11 = -a22 * a10 + a12 * a20;
  float b21 = a21 * a10 - a11 * a20;

  float det = a00 * b01 + a01 * b11 + a02 * b21;

  return mat3(b01, (-a22 * a01 + a02 * a21), (a12 * a01 - a02 * a11),
              b11, (a22 * a00 - a02 * a20), (-a12 * a00 + a02 * a10),
              b21, (-a21 * a00 + a01 * a20), (a11 * a00 - a01 * a10)) / det;
}

vec3 viewToWorld(vec3 viewPosition) {
    vec4 pos;
    pos.xyz = viewPosition;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}
vec3 worldToView(vec3 worldPos) {
    vec4 pos = vec4(worldPos, 0.0);
    pos = gbufferModelView * pos;
    return pos.xyz;
}
vec4 encode (vec3 n, vec2 lightmaps){
	n.xy = n.xy / dot(abs(n), vec3(1.0));
	n.xy = n.z <= 0.0 ? (1.0 - abs(n.yx)) * sign(n.xy) : n.xy;
    vec2 encn = clamp(n.xy * 0.5 + 0.5,-1.0,1.0);
	
    return vec4(encn,vec2(lightmaps.x,lightmaps.y));
}

//encoding by jodie
float encodeVec2(vec2 a){
    const vec2 constant1 = vec2( 1., 256.) / 65535.;
    vec2 temp = floor( a * 255. );
	return temp.x*constant1.x+temp.y*constant1.y;
}
float encodeVec2(float x,float y){
    return encodeVec2(vec2(x,y));
}

#ifdef MC_NORMAL_MAP
	vec3 applyBump(mat3 tbnMatrix, vec3 bump){
		float bumpmult = NORMAL_MAP_MULT;
		bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);
		return normalize(bump*tbnMatrix);
	}
#endif


#ifndef diagonal3
#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#endif
#ifndef projMAD
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
#endif

vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}
vec3 toClipSpace3(vec3 viewSpacePosition) {
    return projMAD(gbufferProjection, viewSpacePosition) / -viewSpacePosition.z * 0.5 + 0.5;
}

#ifdef POM
	vec4 readNormal(in vec2 coord)
	{
		return texture2DGradARB(normals,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dcdx,dcdy);
	}
	vec4 readTexture(in vec2 coord)
	{
		return texture2DGradARB(texture,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dcdx,dcdy);
	}
#endif


float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}


vec3 toLinear(vec3 sRGB){
	return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}


const vec2[8] offsets = vec2[8](vec2(1./8.,-3./8.),
									vec2(-1.,3.)/8.,
									vec2(5.0,1.)/8.,
									vec2(-3,-5.)/8.,
									vec2(-5.,5.)/8.,
									vec2(-7.,-1.)/8.,
									vec2(3,7.)/8.,
									vec2(7.,-7.)/8.);


uniform float near;


float ld(float dist) {
    return (2.0 * near) / (far + near - dist * (far - near));
}


vec4 readNoise(in vec2 coord){
	// return texture2D(noisetex,coord*vtexcoordam.pq+vtexcoord.st);
		return texture2DGradARB(noisetex,coord*vtexcoordam.pq + vtexcoordam.st,dcdx,dcdy);
}
float EndPortalEffect(
	inout vec4 ALBEDO,
	vec3 FragPos,
	vec3 WorldPos,
	mat3 tbnMatrix
){	

	int maxdist = 25;
	int quality = 35;

	vec3 viewVec = normalize(tbnMatrix*FragPos);
	if ( viewVec.z < 0.0 && length(FragPos) < maxdist) {
		float endportalGLow = 0.0;
		float Depth = 0.3;
		vec3 interval = (viewVec.xyz /-viewVec.z/quality*Depth) * (0.7 + (blueNoise()-0.5)*0.1);

		vec3 coord = vec3(WorldPos.xz , 1.0);
		coord += interval;

		for (int loopCount = 0; (loopCount < quality) && (1.0 - Depth + Depth * ( 1.0-readNoise(coord.st).r - readNoise(-coord.st*3).b*0.2 ) ) < coord.p  && coord.p >= 0.0; ++loopCount) {
			coord = coord+interval ; 
			endportalGLow += (0.3/quality);
		}

  		ALBEDO.rgb = vec3(0.5,0.75,1.0) * sqrt(endportalGLow);

		return clamp(pow(endportalGLow*3.5,3),0,1);
	}
}

float bias(){
	// return (Texture_MipMap_Bias + (blueNoise()-0.5)*0.5) - (1.0-RENDER_SCALE.x) * 2.0;
	return Texture_MipMap_Bias - (1.0-RENDER_SCALE.x) * 2.0;
}
vec4 texture2D_POMSwitch(
	sampler2D sampler, 
	vec2 lightmapCoord,
	vec4 dcdxdcdy, 
	bool ifPOM,
	float LOD
){
	if(ifPOM){
		return texture2DGradARB(sampler, lightmapCoord, dcdxdcdy.xy, dcdxdcdy.zw);
	}else{
		return texture2D(sampler, lightmapCoord, LOD);
	}
}

uniform vec3 eyePosition;

void convertHandDepth(inout float depth) {
    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;
    depth = ndcDepth * 0.5 + 0.5;
}

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

// IntegratedPBR+ environment and helpers.  The globals must exist before the
// helper functions that read them, and both must exist before main().
#include "/lib/ipbr/ipbr_globals.glsl"
#include "/lib/ipbr/ipbr_compat.glsl"

#if defined HAND || defined ENTITIES || defined BLOCKENTITIES
	/* RENDERTARGETS:1,8,15,2 */
#else
	/* RENDERTARGETS:1,8,15 */
#endif

void main() {
		
	vec3 FragCoord = gl_FragCoord.xyz;

	#ifdef HAND
		convertHandDepth(FragCoord.z);
	#endif
	
	bool ifPOM = false;

	#ifdef POM
		ifPOM = true;
	#endif

	if(SIGN > 0) ifPOM = false;

	vec3 normal = normalMat.xyz;

	#ifdef MC_NORMAL_MAP
		vec3 binormal = normalize(cross(tangent.rgb,normal)*tangent.w);
		mat3 tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
							  tangent.y, binormal.y, normal.y,
							  tangent.z, binormal.z, normal.z);
	#endif

	vec2 tempOffset = offsets[framemod8];

	vec3 fragpos = toScreenSpace(FragCoord*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5, 0.0));
	vec3 playerpos = mat3(gbufferModelViewInverse) * fragpos  + gbufferModelViewInverse[3].xyz;
	vec3 worldpos = playerpos + cameraPosition;

	float torchlightmap = lmtexcoord.z;

	#if defined Hand_Held_lights && !defined IS_LPV_ENABLED
		#ifdef IS_IRIS
			vec3 playerCamPos = eyePosition;
		#else
			vec3 playerCamPos = cameraPosition;
		#endif

		#ifdef VIVECRAFT
        	if (vivecraftIsVR) { 
				playerCamPos = cameraPosition - vivecraftRelativeMainHandPos;
			}
		#endif

		// if(HELD_ITEM_BRIGHTNESS > 0.0) torchlightmap = max(torchlightmap, HELD_ITEM_BRIGHTNESS * clamp( pow(max(1.0-length(worldpos-playerCamPos)/HANDHELD_LIGHT_RANGE,0.0),1.5),0.0,1.0));
		if(HELD_ITEM_BRIGHTNESS > 0.0){ 
			
			float pointLight = clamp(1.0-(length(worldpos-playerCamPos)-1)/HANDHELD_LIGHT_RANGE,0.0,1.0);
			
			torchlightmap = mix(torchlightmap, HELD_ITEM_BRIGHTNESS, pointLight);
		}

		#ifdef HAND
			torchlightmap *= 0.9;
		#endif
	#endif
	
	float lightmap = clamp( (lmtexcoord.w-0.9) * 10.0,0.,1.);

	vec2 adjustedTexCoord = lmtexcoord.xy;

#if defined POM && defined WORLD && !defined ENTITIES && !defined HAND
	// vec2 tempOffset=offsets[framemod8];
	adjustedTexCoord = fract(vtexcoord.st)*vtexcoordam.pq+vtexcoordam.st;
	// vec3 fragpos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize/RENDER_SCALE,1.0)-vec3(vec2(tempOffset)*texelSize*0.5,0.0));
	vec3 viewVector = normalize(tbnMatrix*fragpos);
	float dist = length(playerpos);

	float falloff = min(max(1.0-dist/MAX_OCCLUSION_DISTANCE,0.0) * 2.0,1.0);

	falloff = pow(1.0-pow(1.0-falloff,1.0),2.0);

	// falloff =  1;

	float maxdist = MAX_OCCLUSION_DISTANCE;
	if(!ifPOM) maxdist = 0.0;

	gl_FragDepth = gl_FragCoord.z;
	if (falloff > 0.0) {

		float depthmap = readNormal(vtexcoord.st).a;
		float used_POM_DEPTH = 1.0;
		float pomdepth = POM_DEPTH*falloff;

 		if ( viewVector.z < 0.0 && depthmap < 0.9999 && depthmap > 0.00001) {	
			float noise = blueNoise();
			#ifdef Adaptive_Step_length
				vec3 interval = (viewVector.xyz /-viewVector.z/MAX_OCCLUSION_POINTS * pomdepth) * clamp(1.0-pow(depthmap,2),0.1,1.0);
				used_POM_DEPTH = 1.0;
			#else
				vec3 interval = viewVector.xyz /-viewVector.z/MAX_OCCLUSION_POINTS*pomdepth;
			#endif
			vec3 coord = vec3(vtexcoord.st , 1.0);

			coord += interval * noise * used_POM_DEPTH;

			float sumVec = noise;
			for (int loopCount = 0; (loopCount < MAX_OCCLUSION_POINTS) && (1.0 - pomdepth + pomdepth * readNormal(coord.st).a  ) < coord.p  && coord.p >= 0.0; ++loopCount) {
				coord = coord + interval  * used_POM_DEPTH; 
				sumVec += used_POM_DEPTH; 
			}
	
			if (coord.t < mincoord) {
				if (readTexture(vec2(coord.s,mincoord)).a == 0.0) {
					coord.t = mincoord;
					discard;
				}
			}
			
			adjustedTexCoord = mix(fract(coord.st)*vtexcoordam.pq+vtexcoordam.st, adjustedTexCoord, max(dist-MIX_OCCLUSION_DISTANCE,0.0)/(MAX_OCCLUSION_DISTANCE-MIX_OCCLUSION_DISTANCE));

			vec3 truePos = fragpos + sumVec*inverseMatrix(tbnMatrix)*interval;

			gl_FragDepth = toClipSpace3(truePos).z;
		}
	}
#endif
	if(!ifPOM) adjustedTexCoord = lmtexcoord.xy;
	

	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	ALBEDO		////////////////////////////////
	//////////////////////////////// 				//////////////////////////////// 
	float textureLOD = bias();

	#ifdef IPBR
		// Keep the raw texture sample: Complementary's grounded materials work
		// off the texture colour before the vertex colour is applied.
		vec4 ipbrTexSample = texture2D_POMSwitch(texture, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM, textureLOD);
		vec4 Albedo = ipbrTexSample * vColor;
	#else
		vec4 Albedo = texture2D_POMSwitch(texture, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM, textureLOD) * vColor;
	#endif
	
	
	#if defined HAND
		if (Albedo.a < 0.1) discard;
	#endif

	// -----------------------------------------------------------------------
	//  IntegratedPBR+ material database
	// -----------------------------------------------------------------------
	#include "/lib/ipbr/ipbr_solid.glsl"

	#if defined IPBR && (defined ENTITIES || defined HAND)
		if (Albedo.a < 0.1) discard;
	#endif

	if(LIGHTNING > 0) Albedo = vec4(1);

	#if  defined WORLD && !defined ENTITIES && !defined HAND
	float endPortalEmission = 0.0;
	if(PORTAL > 0) {
		float steps = 20;

		vec3 color = vec3(0.0);
		float absorbance = 1.0;

		vec3 worldSpaceNormal = viewToWorld(normal);

		vec3 viewVec = normalize(tbnMatrix*fragpos);
		vec3 correctedViewVec = viewVec;
		if(PORTAL > 0){
		correctedViewVec.xy = mix(correctedViewVec.xy, vec2( viewVec.y,-viewVec.x), clamp( worldSpaceNormal.y,0,1));
		correctedViewVec.xy = mix(correctedViewVec.xy, vec2(-viewVec.y, viewVec.x), clamp(-worldSpaceNormal.x,0,1)); 
		correctedViewVec.xy = mix(correctedViewVec.xy, vec2(-viewVec.y, viewVec.x), clamp(-worldSpaceNormal.z,0,1));
		}
		correctedViewVec.z = mix(correctedViewVec.z, -correctedViewVec.z, clamp(length(vec3(worldSpaceNormal.xz, clamp(-worldSpaceNormal.y,0,1))),0,1)); 
		
		vec2 correctedWorldPos = playerpos.xz + cameraPosition.xz;
		correctedWorldPos = mix(correctedWorldPos,	vec2(-playerpos.x,playerpos.z)	+	vec2(-cameraPosition.x,cameraPosition.z),	clamp(-worldSpaceNormal.y,0,1));
		correctedWorldPos = mix(correctedWorldPos,	vec2( playerpos.z,playerpos.y)	+	vec2( cameraPosition.z,cameraPosition.y),	clamp( worldSpaceNormal.x,0,1));
		correctedWorldPos = mix(correctedWorldPos,	vec2(-playerpos.z,playerpos.y)	+	vec2(-cameraPosition.z,cameraPosition.y),	clamp(-worldSpaceNormal.x,0,1));
		correctedWorldPos = mix(correctedWorldPos,	vec2( playerpos.x,playerpos.y)	+	vec2( cameraPosition.x,cameraPosition.y),	clamp(-worldSpaceNormal.z,0,1));
		correctedWorldPos = mix(correctedWorldPos,	vec2(-playerpos.x,playerpos.y)	+	vec2(-cameraPosition.x,cameraPosition.y),	clamp( worldSpaceNormal.z,0,1));


		vec2 rayDir = ((correctedViewVec.xy) / -correctedViewVec.z) / steps * 5.0 ;
	
		vec2 uv = correctedWorldPos + rayDir * blueNoise();
		uv += rayDir * 10.0;

		vec2 animation = vec2(frameTimeCounter, -frameTimeCounter)*0.01;
		
		for (int i = 0; i < int(steps); i++) {
			
			float verticalGradient = (i + blueNoise())/steps ;
			float verticalGradient2 = exp(-7*(1-verticalGradient*verticalGradient));
		
			float density = max(max(verticalGradient - texture2D(noisetex, uv/256.0 + animation.xy).b*0.5,0.0) - (1.0-texture2D(noisetex, uv/32.0 + animation.xx).r) * (0.4 + 0.1 * (texture2D(noisetex, uv/10.0 - animation.yy).b)),0.0);
		
			float volumeCoeff = exp(-density*(i+1));
			
			vec3 lighting =  vec3(0.5,0.75,1.0) * 0.1 * exp(-10*density) + vec3(0.2,0.7,1.0) * verticalGradient2 * 2.0;
			color += (lighting - lighting * volumeCoeff) * absorbance;;

			absorbance *= volumeCoeff;
			endPortalEmission += verticalGradient*verticalGradient ;
			uv += rayDir;
		}

		Albedo.rgb = clamp(color,0,1);
		endPortalEmission = clamp(endPortalEmission/steps * 1.0,0.0,254.0/255.0);
		
	}
	#endif
	
	#ifdef WhiteWorld
		Albedo.rgb = vec3(0.5);
	#endif

		
	#ifdef AEROCHROME_MODE
		float gray = dot(Albedo.rgb, vec3(0.2, 1.0, 0.07));
		if (
			blockID == BLOCK_AMETHYST_BUD_MEDIUM || blockID == BLOCK_AMETHYST_BUD_LARGE || blockID == BLOCK_AMETHYST_CLUSTER 
			|| blockID == BLOCK_SSS_STRONG || blockID == BLOCK_SSS_WEAK
			|| blockID == BLOCK_GLOW_LICHEN || blockID == BLOCK_SNOW_LAYERS
			|| blockID >= 10 && blockID < 80
		) {
			// IR Reflective (Pink-red)
			Albedo.rgb = mix(vec3(gray), aerochrome_color, 0.7);
		}
		else if(blockID == BLOCK_GRASS) {
		// Special handling for grass block
			float strength = 1.0 - vColor.b;
			Albedo.rgb = mix(Albedo.rgb, aerochrome_color, strength);
		}
		#ifdef AEROCHROME_WOOL_ENABLED
			else if (blockID == BLOCK_SSS_WEAK_2 || blockID == BLOCK_CARPET) {
			// Wool
				Albedo.rgb = mix(Albedo.rgb, aerochrome_color, 0.3);
			}
		#endif
		else if(blockID == BLOCK_WATER || (blockID >= 300 && blockID < 400))
		{
		// IR Absorbsive? Dark.
			Albedo.rgb = mix(Albedo.rgb, vec3(0.01, 0.08, 0.15), 0.5);
		}
	#endif

	#ifdef WORLD
		if (Albedo.a > 0.1) Albedo.a = normalMat.a;
		else Albedo.a = 0.0;
	#endif

	#ifdef HAND
		if (Albedo.a > 0.1){
			Albedo.a = 0.75;
			gl_FragData[3] = vec4(0.0);
		} else {
			Albedo.a = 1.0;
		}
	#endif
	#if defined PARTICLE_RENDERING_FIX && (defined ENTITIES || defined BLOCKENTITIES)
		gl_FragData[3] = vec4(0.0);
	#endif

	
	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	NORMAL		////////////////////////////////
	//////////////////////////////// 				//////////////////////////////// 

	// IntegratedPBR+ supplies its own normal (integratedPBR+ has no resource-pack
	// normal maps; that is what the LabPBR mode of the toggle is for).
	#if defined WORLD && defined MC_NORMAL_MAP && !defined IPBR
		vec4 NormalTex = texture2D_POMSwitch(normals, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM,textureLOD).xyzw;
		
		#ifdef MATERIAL_AO
			Albedo.rgb *= NormalTex.b*0.5+0.5;
		#endif

		float Heightmap = 1.0 - NormalTex.w;

		NormalTex.xy = NormalTex.xy * 2.0-1.0;
		NormalTex.z = sqrt(max(1.0 - dot(NormalTex.xy, NormalTex.xy), 0.0));

		normal = applyBump(tbnMatrix, NormalTex.xyz);
	#endif
	
	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	SPECULAR	////////////////////////////////
	//////////////////////////////// 				//////////////////////////////// 
	
	#ifdef WORLD
		#ifdef IPBR
			// ---------------- IntegratedPBR+ material write ----------------
			// colortex8.r  perceptual smoothness
			// colortex8.g  F0, so Bliss' Fresnel/reflection model reacts to
			//              the material the same way Complementary's does
			// colortex8.b  subsurface scattering
			// colortex8.a  emission (Bliss raises it to Emissive_Curve, which
			//              is the same squaring Complementary does)
			// Reflections follow smoothnessD like upstream (0 for grass, dirt, sand); smoothnessG only shapes the highlight.
			float ipbrSmoothness = clamp(smoothnessD, 0.0, 1.0);

			// ------------------------------------------------------------------
			// F0 mapping.
			//
			// Bliss gates every reflection behind `getReflectionVisibility`
			// (lib/specular.glsl), which opens at an F0 threshold of 26/255:
			//
			//     float dialectrics = max(f0*255.0 - 26.0,0.0)/229.0;
			//
			// Below that threshold visibility is exactly zero, so this base has
			// to clear it or the material reflects nothing at all -- which is
			// what a 0.05 base did, and why tuning the grazing floors by a
			// factor of four changed almost nothing: both were still under the
			// gate, not merely weak.
			//
			// Complementary multiplies a fixed Fresnel by highlightMult and
			// gives virtually every surface some reflection.  Placing the base
			// just above the threshold reproduces that: a default material lands
			// at 0.11, opening visibility at ~0.01 -- a faint near-mirror sheen
			// rather than a visible gloss, and present head-on so it survives in
			// shade.
			//
			// IPBR_SPECULAR_STRENGTH scales every material from here.
			// ------------------------------------------------------------------
			float ipbrF0 = clamp(IPBR_SPECULAR_STRENGTH_M * 0.11 * sqrt(max(highlightMult, 0.0)), 0.0, 0.99);

			// Complementary tags metals and shiny-hard blocks with a coloured
			// fresnel instead of an F0.  Bliss already has LabPBR's hardcoded
			// metal reflectances, so translate them and let Bliss render the
			// metal properly.
			if      (materialMask > OSIEBCA * 1.5 && materialMask < OSIEBCA * 2.5) ipbrF0 = 234.0 / 255.0; // copper
			else if (materialMask > OSIEBCA * 2.5 && materialMask < OSIEBCA * 3.5) ipbrF0 = 231.0 / 255.0; // gold
			else if (materialMask > OSIEBCA * 4.5 && materialMask < OSIEBCA * 5.5) ipbrF0 = 230.0 / 255.0; // redstone -> iron
			// OSIEBCA * 1.0 is Complementary's "Intense Fresnel": a brighter
			// reflection tint, not a metal.  Iron, quartz, obsidian, amethyst,
			// OSIEBCA * 1.0 is Complementary's "Intense Fresnel": iron, quartz,
			// obsidian, amethyst, diamond, emerald, deepslate.  Upstream it
			// replaces the Fresnel curve with `fresnelM * 0.75 + 0.25`
			// (deferred1.glsl), i.e. a 0.25 reflectance floor even head-on.
			// Bliss' F0 is that floor.
			else if (materialMask > OSIEBCA * 0.5 && materialMask < OSIEBCA * 1.5) {
				ipbrF0 = max(ipbrF0, 0.25 * IPBR_INTENSE_FRESNEL_MULT_M);
			}

			// ------------------------------------------------------------------
			// Grazing-angle sheen, applied last so it lifts the floor for every
			// material rather than competing with the metal and intense-fresnel
			// cases above.  max() means it can only raise a value, never lower
			// one, so those cases keep the reflectances they were given.
			//
			// Fresnel suppresses the reflection at normal incidence, so floors
			// here read as a rough sheen that appears as the angle shallows --
			// the Complementary behaviour -- rather than as an all-over gloss.
			// ------------------------------------------------------------------
			#ifdef IPBR_GRAZING_REFLECTIONS
				ipbrSmoothness = max(ipbrSmoothness, IPBR_GRAZING_SMOOTHNESS);
				ipbrF0 = max(ipbrF0, IPBR_GRAZING_F0);
			#endif

			if (ipbrF0 > 229.5 / 255.0) {
				ipbrSmoothness = max(ipbrSmoothness, clamp(smoothnessG, 0.0, 1.0));
			} else {
				// Dielectric F0 channel = 0.45 intense-fresnel flag + 0.44 * smoothnessG; decoded in specular.glsl.
				bool ipbrIntense = materialMask > OSIEBCA * 0.5 && materialMask < OSIEBCA * 1.5;
				ipbrF0 = (ipbrIntense ? 0.45 : 0.0) + 0.44 * clamp(smoothnessG, 0.0, 1.0);
			}

			// ------------------------------------------------------------------
		// TEMPORARY TEST -- specular aliasing on near-Nyquist synthetic normals.
		//
		// A resource-pack normal map is hand-authored and smooth.  GenerateNormals
		// differences ADJACENT TEXELS of a 16x16 texture, which is close to the
		// Nyquist limit that texture can express -- opposite ends of the frequency
		// spectrum, fed into the same specular pipeline.
		//
		// A real normal texture has a mip chain, so local variance can be inspected
		// and roughness widened to suppress specular aliasing.  A synthetic
		// per-fragment normal has no mip chain and no such mechanism, so every
		// texel-scale wobble gets full-contrast specular response.  That predicts a
		// hard, texture-locked, angle-invariant artifact unaffected by perturbation
		// magnitude -- and that widening the sample footprint makes it worse, which
		// is what four-step averaging did.
		//
		//   mesh disappears or drops to a faint diffuse-only version -> specular
		//        aliasing.  The fix is to widen roughness in proportion to the
		//        synthetic normal's variance, not to keep editing the gradient.
		//   mesh unchanged -> specular is excluded and the pattern is not a
		//        lighting response at all, which makes item #1's contradiction
		//        the thing to resolve.
		// ------------------------------------------------------------------
		// ------------------------------------------------------------------
		// Diagnostic switch, enabled from the shaderpack options file with
		//     GN_TEST_TINT=true
		// Paints the albedo an unmissable colour wherever the IPBR path runs, so
		// a capture proves at a glance that the modified shader is the one being
		// rendered -- ruling out a stale build or a failed reload before any
		// conclusion is drawn from the image.
		// ------------------------------------------------------------------
		#ifdef GN_TEST_TINT
			Albedo.rgb = vec3(1.0, 0.0, 1.0);
		#endif

		gl_FragData[1].rg = vec2(ipbrSmoothness, ipbrF0);
			gl_FragData[1].a = IpbrToBlissEmission(emission);

			float ipbrSSS = 0.0;
			if      (subsurfaceMode == 1) ipbrSSS = 0.75;
			else if (subsurfaceMode == 2) ipbrSSS = 0.50;
			else if (subsurfaceMode == 3) ipbrSSS = 0.40;
			#if SSS_TYPE == 1 || SSS_TYPE == 2
				ipbrSSS = max(ipbrSSS, SSSAMOUNT);
			#endif
			gl_FragData[1].b = ipbrSSS;

			#if defined WORLD && !defined ENTITIES && !defined HAND
				if(PORTAL > 0) gl_FragData[1].a = endPortalEmission;
			#endif

			#if DEBUG_VIEW == debug_MATERIAL_SSS
				Albedo.rgb = vec3(0.1);
				if(ipbrSSS > 0.0) Albedo.rgb = vec3(0.0,ipbrSSS,0.0);
			#endif
			#if DEBUG_VIEW == debug_MATERIAL_EMISSION
				Albedo.rgb = vec3(0.1);
				if(emission > 0.0) Albedo.rgb = vec3(0.0, emission, 0.0);
				if(emission >= 1.0) Albedo.rgb = vec3(1.0,0.0,0.0);
			#endif
			// Verification aids for the IntegratedPBR+ port: they show what the
			// material database resolved for this fragment.
			#if DEBUG_VIEW == debug_MATERIAL_ID
				// Brighter = higher Complementary material id.  Anything close
				// to black means the block is not in the IPBR database.
				Albedo.rgb = vec3(clamp(float(mat) / 3000.0, 0.0, 4.0));
			#endif
			#if DEBUG_VIEW == debug_SMOOTHNESS
				Albedo.rgb = vec3(ipbrSmoothness);
			#endif
			#if DEBUG_VIEW == debug_IPBR_EMISSION
				Albedo.rgb = vec3(clamp(emission, 0.0, 1.0));
			#endif
			#if DEBUG_VIEW == debug_GENERATED_NORMALS
				// Reports what the REAL GenerateNormals computed, recorded from
				// inside it.  The normal render is not shown here because a flat
				// field is ambiguous -- it looks the same whether the function
				// never ran, ran and produced (0,0), or ran and was discarded.
				//
				//   red   = 1 if GenerateNormals reached its final line at all
				//   green = |normalMap.x| x 4      (0 = all four diffs thresholded away)
				//   blue  = |normalMap.y| x 4
				//
				// Whole screen BLACK (red 0) means the function never completed --
				// it is not being called, returning early, or the assignment is not
				// reaching this scope.  Red 1 with black green/blue means GetDif is
				// returning exactly 0 for every sample.
				Albedo.rgb = vec3(ipbrGNDebug.w > 0.5 ? 1.0 : 0.0,
				                  clamp(abs(ipbrGNDebug.y) * 4.0, 0.0, 1.0),
				                  clamp(abs(ipbrGNDebug.z) * 4.0, 0.0, 1.0));
			#endif
			#if DEBUG_VIEW == debug_TANGENT
				// Reports the atlas size actually resolved at runtime, which is what
				// the generated-normal sample offset is computed from:
				//
				//     offsetR = 16.0 / atlasSizeM / GENERATED_NORMAL_RES
				//
				// so a wrong atlas size means the samples land the wrong distance
				// apart.  That would be a fixed distance in UV space -- identical
				// from every camera angle, unaffected by GENERATED_NORMAL_MULT and
				// unaffected by the shape of GetDif's compression, which is exactly
				// the behaviour observed.
				//
				//   red = atlasSizeM.x / 4096, green = atlasSizeM.y / 4096
				//
				// Flat 0.25/0.25 means textureSize() failed and the 1024 fallback is
				// in use.  Any other flat value is the real atlas size, and
				// offset-in-texels = 0.125 x 1024 / (that value) tells us how far
				// off the sampling is.
				Albedo.rgb = vec3(ipbrAtlasSizeDebug.x / 4096.0,
				                  ipbrAtlasSizeDebug.y / 4096.0,
				                  0.0);
			#endif
			#if 0
				// Is the vertex tangent consistent across a block face?
				//
				// A block face is two triangles split along a diagonal.  If
				// at_tangent differs between them -- Iris/Sodium generate it
				// per-face rather than truly per-vertex in some versions --
				// interpolating it rotates the tangent frame along that shared
				// edge, which rotates the generated-normal relief axes with it
				// and shows up as a hard diagonal seam that moves with the
				// camera.
				//
				//   red/green/blue = tangent.rgb * 0.5 + 0.5
				//   a HARD COLOUR DISCONTINUITY ALONG THE DIAGONAL means the
				//   tangent is per-triangle inconsistent and the vertex-tangent
				//   path is the problem
				//   smooth colour means it is consistent and the fault is
				//   downstream (the branch selection, or ipbrB reconstruction)
				//
				// A unit tangent maps every channel into 0.21-0.79.
				Albedo.rgb = clamp(tangent.rgb * 0.5 + 0.5, 0.0, 1.0);
			#endif
			#if DEBUG_VIEW == debug_SPRITE_SIZE
				// State of the final normal safety net.
				//
				//   red   = 1 if it replaced normalM with the geometric normal
				//   green = |normalM|^2 before it ran  (~1 when GenerateNormals
				//           assigned a perturbed normal)
				//   blue  = |normalM|^2 after
				//
				// Red-on means the safety net is what discards generated normals.
				// Red-off with green ~1 means normalM is valid and the loss is at
				// `normal = normalM`.
				Albedo.rgb = vec3(ipbrNormalDebug.x,
				                  clamp(ipbrNormalDebug.y, 0.0, 1.0),
				                  clamp(ipbrNormalDebug.z, 0.0, 1.0));
			#endif
			#if DEBUG_VIEW == debug_TEXTURE_GRADIENT
				// An inline replication of GenerateNormals, using the SAME offset,
				// the same sampling and the same threshold as the real path.
				//
				// This used to use fwidth() for the offset and implicit-LOD
				// texture2D() for the samples.  Both were removed from the real
				// path and ruled out as causes, but the replica was never updated,
				// so it had been reproducing stale behaviour -- showing a mesh
				// produced by two things that no longer exist in the code under
				// test.  It now mirrors generatedNormals.glsl exactly:
				//
				//   offsetR = originalOffsetR          (no fwidth floor)
				//   texture2DLod(..., 0.0)             (no implicit LOD)
				//
				//   mesh visible here -> the gradients themselves carry it, and
				//        the cause is in this sampling
				//   clean here       -> the gradients are fine and whatever shows
				//        in the world comes from elsewhere
				float ipbrThr = 0.05;
				vec2 ipbrO = (16.0 / atlasSizeM) / float(GENERATED_NORMAL_RES);
				float ipbrCc = length(texture2D(texture, texCoord).rgb);

				float ipbrDR = ipbrCc - length(texture2D(texture, texCoord + vec2(ipbrO.x, 0.0)).rgb);
				float ipbrDL = ipbrCc - length(texture2D(texture, texCoord - vec2(ipbrO.x, 0.0)).rgb);
				float ipbrDU = ipbrCc - length(texture2D(texture, texCoord + vec2(0.0, ipbrO.y)).rgb);
				float ipbrDD = ipbrCc - length(texture2D(texture, texCoord - vec2(0.0, ipbrO.y)).rgb);
				// Same smooth compression as generatedNormals.glsl.  This replica has
				// to track the real path exactly, or it measures the wrong thing.
				float ipbrCl = 0.2;
				ipbrDR = ipbrDR >= 0.0 ?  ipbrCl * (1.0 - exp(-ipbrDR / ipbrThr)) : -ipbrCl * (1.0 - exp( ipbrDR / ipbrThr));
				ipbrDL = ipbrDL >= 0.0 ?  ipbrCl * (1.0 - exp(-ipbrDL / ipbrThr)) : -ipbrCl * (1.0 - exp( ipbrDL / ipbrThr));
				ipbrDU = ipbrDU >= 0.0 ?  ipbrCl * (1.0 - exp(-ipbrDU / ipbrThr)) : -ipbrCl * (1.0 - exp( ipbrDU / ipbrThr));
				ipbrDD = ipbrDD >= 0.0 ?  ipbrCl * (1.0 - exp(-ipbrDD / ipbrThr)) : -ipbrCl * (1.0 - exp( ipbrDD / ipbrThr));

				vec3 ipbrNrm = vec3(0.0, 0.0, 1.0);
				ipbrNrm.x = ipbrDR - ipbrDL;
				ipbrNrm.y = ipbrDU - ipbrDD;
				ipbrNrm.xy *= 2.5;
				ipbrNrm.xy = clamp(ipbrNrm.xy, vec2(-1.0), vec2(1.0));

				if (ipbrNrm.xy != vec2(0.0, 0.0)) {
					Albedo.rgb = normalize(ipbrNrm * tbnMatrix) * 0.5 + 0.5;
				} else {
					Albedo.rgb = vec3(1.0, 0.0, 0.0);
				}
			#endif

			// Debug values are written into the albedo, which the deferred pass
			// then lights -- so without this a debug view shows the *lighting*
			// and the value is unreadable.  Forcing near-full emission makes
			// the result unlit; the 0.2 pre-scale cancels the 5x emissive gain.
			#if DEBUG_VIEW == debug_MATERIAL_ID || DEBUG_VIEW == debug_SMOOTHNESS || DEBUG_VIEW == debug_IPBR_EMISSION || DEBUG_VIEW == debug_GENERATED_NORMALS || DEBUG_VIEW == debug_SPRITE_SIZE || DEBUG_VIEW == debug_TEXTURE_GRADIENT || DEBUG_VIEW == debug_TANGENT || DEBUG_VIEW == debug_MATERIAL_SSS || DEBUG_VIEW == debug_MATERIAL_EMISSION
				Albedo.rgb *= 0.2;
				gl_FragData[1].a = 254.0 / 255.0;
			#endif
		#else
		vec4 SpecularTex = texture2D_POMSwitch(specular, adjustedTexCoord.xy, vec4(dcdx,dcdy), ifPOM,textureLOD);

		// SpecularTex.r = max(SpecularTex.r, rainfall);
		// SpecularTex.g = max(SpecularTex.g, max(Puddle_shape*0.02,0.02));

		gl_FragData[1].rg = SpecularTex.rg;

		#if EMISSIVE_TYPE == 0
			gl_FragData[1].a = 0.0;
		#endif

		#if EMISSIVE_TYPE == 1
			gl_FragData[1].a = EMISSIVE;
		#endif

		#if EMISSIVE_TYPE == 2
			gl_FragData[1].a = SpecularTex.a;
			if(SpecularTex.a <= 0.0) gl_FragData[1].a = EMISSIVE;
		#endif

		#if EMISSIVE_TYPE == 3		
			gl_FragData[1].a = SpecularTex.a;
		#endif
		
		#if  defined WORLD && !defined ENTITIES && !defined HAND
			if(PORTAL > 0) gl_FragData[1].a = endPortalEmission;
		#endif

		#if SSS_TYPE == 0
			gl_FragData[1].b = 0.0;
		#endif

		#if SSS_TYPE == 1
			gl_FragData[1].b = SSSAMOUNT;
		#endif

		#if SSS_TYPE == 2
			gl_FragData[1].b = SpecularTex.b;
			if(SpecularTex.b < 65.0/255.0) gl_FragData[1].b = SSSAMOUNT;
		#endif

		#if SSS_TYPE == 3		
			gl_FragData[1].b = SpecularTex.b;
		#endif

		#if DEBUG_VIEW == debug_MATERIAL_SSS
			Albedo.rgb = vec3(0.1);
			if(SSSAMOUNT > 0.0) Albedo.rgb = vec3(0.0,SSSAMOUNT,0.0);
		#endif
		#if DEBUG_VIEW == debug_MATERIAL_EMISSION
			Albedo.rgb = vec3(0.1);
			if(EMISSIVE > 0.0) Albedo.rgb = vec3(0.0,EMISSIVE,0.0);
			if(EMISSIVE >= 1.0) Albedo.rgb = vec3(1.0,0.0,0.0);
		#endif
		#endif // IPBR
	#endif

	// hit glow effect...
	#ifdef ENTITIES
		Albedo.rgb = mix(Albedo.rgb, entityColor.rgb, clamp(entityColor.a*1.5,0,1));
	#endif

	//////////////////////////////// 				////////////////////////////////
	////////////////////////////////	FINALIZE	////////////////////////////////
	//////////////////////////////// 				////////////////////////////////

	#if DEBUG_VIEW == debug_LIGHTMAPS
		Albedo.rgb = vec3(lmtexcoord.z,lmtexcoord.w,0.0);
	#endif

	#ifdef WORLD
		// apply noise to lightmaps to reduce banding.
		vec2 PackLightmaps = vec2(torchlightmap, lmtexcoord.w);
		vec4 data1 = clamp( encode(viewToWorld(normal), PackLightmaps), 0.0, 1.0);

		// encodeVec2 is 8-bit: IPBR tables brighten albedo past 1.0, which would wrap.
		Albedo.rgb = clamp(Albedo.rgb, 0.0, 1.0);

		gl_FragData[0] = vec4(encodeVec2(Albedo.x,data1.x),	encodeVec2(Albedo.y,data1.y),	encodeVec2(Albedo.z,data1.z),	encodeVec2(data1.w,Albedo.w));

		gl_FragData[2] = vec4(viewToWorld(FlatNormals) * 0.5 + 0.5, VanillaAO);	
	#endif
	
}
