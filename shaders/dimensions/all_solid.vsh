
#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/bokeh.glsl"
#include "/lib/blocks.glsl"
#include "/lib/entities.glsl"
#include "/lib/items.glsl"
#include "/lib/ipbr/ipbr_settings.glsl"
#include "/lib/ipbr/id_decode.glsl"

/*
!! DO NOT REMOVE !!
This code is from Chocapic13' shaders
Read the terms of modification and sharing before changing something below please !
!! DO NOT REMOVE !!
*/


#ifdef HAND
#undef POM
#endif

// IntegratedPBR+ owns the normal in IPBR mode, and it has no heightmap to
// trace, so Bliss' parallax occlusion mapping stands down.
#ifdef IPBR
	#undef POM
#endif

#ifndef MC_NORMAL_MAP
#undef POM
#endif

#ifdef POM
#define MC_NORMAL_MAP
#endif


varying vec4 vColor;
varying float VanillaAO;

varying vec4 lmtexcoord;
varying vec4 normalMat;

// #ifdef POM
	varying vec4 vtexcoordam; // .st for add, .pq for mul
	varying vec4 vtexcoord;
// #endif

// FlatNormals is used unconditionally by the fragment stage, so it cannot live
// inside the MC_NORMAL_MAP guard.
varying vec3 FlatNormals;

#if defined MC_NORMAL_MAP || defined IPBR_NEEDS_TANGENT
	varying vec4 tangent;
	// TEMPORARY TEST: do not request at_tangent.  GENERATED_NORMALS turns on
	// exactly one thing besides the GenerateNormals call -- IPBR_NEEDS_TANGENT,
	// which reads this attribute.  The call's output is excluded (a constant
	// normal left the mesh unchanged) and so is the varying's use (bypassing
	// tangent.rgb left it unchanged).  The attribute REQUEST has never been
	// excluded: asking Iris/Sodium for at_tangent adds tangent data to the
	// vertex format.  The varying below is still declared and written, just
	// from a constant, so consumers keep compiling.
	attribute vec4 at_tangent;
#endif

uniform float frameTimeCounter;
const float PI48 = 150.796447372*WAVY_SPEED;
float pi2wt = PI48*frameTimeCounter;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

uniform int blockEntityId;
uniform int entityId;
uniform int heldItemId;
uniform int heldItemId2;
uniform int currentRenderedItemId;
flat varying float blockID;

// Raw Iris id (Complementary's `mat`), passed through untouched so the
// fragment stage can run integratedPBR+ against its own numbering.
flat varying float irisBlockId;

// (DecodeBlissBlockId / DecodeBlissBlockIdInt / DecodeBlissEntityIdInt come from lib/ipbr/id_decode.glsl)
int blissEntityId;

flat varying float HELD_ITEM_BRIGHTNESS;



flat varying int NameTags;

uniform int frameCounter;
uniform float far;
uniform float aspectRatio;
uniform float viewHeight;
uniform float viewWidth;
uniform int hideGUI;
uniform float screenBrightness;
uniform int isEyeInWater;

flat varying float SSSAMOUNT;
flat varying float EMISSIVE;
flat varying int LIGHTNING;
flat varying int PORTAL;
flat varying int SIGN;

// in vec3 at_velocity;
// out vec3 velocity;

uniform float nightVision;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform vec2 texelSize;
uniform int framemod8;

#if defined HAND
uniform mat4 gbufferPreviousModelView;
uniform vec3 previousCameraPosition;

float detectCameraMovement(){
	// simply get the difference of modelview matrices and cameraPosition across a frame.
	vec3 fakePos = vec3(0.5,0.5,0.0);
	vec3 hand_playerPos = mat3(gbufferModelViewInverse) * fakePos + (cameraPosition - previousCameraPosition);
	vec3 previousPosition = mat3(gbufferPreviousModelView) * hand_playerPos;
	float detectMovement = 1.0 - clamp(distance(previousPosition, fakePos)/texelSize.x,0.0,1.0);
	
	return detectMovement;
}
#endif

#include "/lib/TAA_jitter.glsl"


							
#ifndef diagonal3
#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#endif
#ifndef projMAD
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
#endif
vec4 toClipSpace3(vec3 viewSpacePosition) {
    return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition),-viewSpacePosition.z);
}

vec2 calcWave(in vec3 pos) {

    float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec2 ret = (sin(pi2wt*vec2(0.0063,0.0015)*4. - pos.xz + pos.y*0.05)+0.1)*magnitude;

    return ret;
}

vec3 calcMovePlants(in vec3 pos) {
    vec2 move1 = calcWave(pos );
	float move1y = -length(move1);
   return vec3(move1.x,move1y,move1.y)*5.*WAVY_STRENGTH;
}

vec3 calcWaveLeaves(in vec3 pos, in float fm, in float mm, in float ma, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5) {

    float magnitude = abs(sin(dot(vec4(frameTimeCounter, pos),vec4(1.0,0.005,0.005,0.005)))*0.5+0.72)*0.013;
	vec3 ret = (sin(pi2wt*vec3(0.0063,0.0224,0.0015)*1.5 - pos))*magnitude;

    return ret;
}

vec3 calcMoveLeaves(in vec3 pos, in float f0, in float f1, in float f2, in float f3, in float f4, in float f5, in vec3 amp1, in vec3 amp2) {
    vec3 move1 = calcWaveLeaves(pos      , 0.0054, 0.0400, 0.0400, 0.0127, 0.0089, 0.0114, 0.0063, 0.0224, 0.0015) * amp1;
    return move1*5.*WAVY_STRENGTH;
}

// float luma(vec3 color) {
// 	return dot(color,vec3(0.21, 0.72, 0.07));
// }

#define SEASONS_VSH
#include "/lib/climate_settings.glsl"


uniform sampler2D noisetex;//depth
float densityAtPos(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	
	//The y channel has an offset to avoid using two textures fetches
	vec2 xy = texture2D(noisetex, coord).yx;

	return mix(xy.r,xy.g, f.y);
}
float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}
vec3 viewToWorld(vec3 viewPos) {
    vec4 pos;
    pos.xyz = viewPos;
    pos.w = 0.0;
    pos = gbufferModelViewInverse * pos;
    return pos.xyz;
}
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {

	gl_Position = ftransform();

	// Resolve both id spaces up front: Iris' raw values drive integratedPBR+,
	// the decoded ones keep every existing Bliss check working.
	blissEntityId = DecodeBlissEntityIdInt(entityId);

	#if defined ENTITIES && defined IS_IRIS
		// force out of frustum
		if (blissEntityId == 1599) gl_Position.z -= 10000.0;
	#endif

	vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;

    /////// ----- COLOR STUFF ----- ///////
	vColor = gl_Color;

	VanillaAO = 1.0 - clamp(vColor.a,0,1);
	if (vColor.a < 0.3) vColor.a = 1.0; // fix vanilla ao on some custom block models.
	


    /////// ----- RANDOM STUFF ----- ///////
	// gl_TextureMatrix[0] for animated things like charged creepers
	lmtexcoord.xy = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	// #ifdef POM
	vec2 midcoord = (gl_TextureMatrix[0] *  mc_midTexCoord).st;
	vec2 texcoordminusmid = lmtexcoord.xy-midcoord;
	vtexcoordam.pq  = abs(texcoordminusmid)*2;
	vtexcoordam.st  = min(lmtexcoord.xy,midcoord-texcoordminusmid);
	vtexcoord.xy    = sign(texcoordminusmid)*0.5+0.5;
	// #endif


	vec2 lmcoord = gl_MultiTexCoord1.xy / 240.0; 
	lmtexcoord.zw = lmcoord;



	#if defined MC_NORMAL_MAP || defined IPBR_NEEDS_TANGENT
		vec3 alterTangent = at_tangent.rgb;

		tangent = vec4(normalize(gl_NormalMatrix * alterTangent.rgb), at_tangent.w);
	#endif

	normalMat = vec4(normalize(gl_NormalMatrix * gl_Normal), 1.0);
	
	FlatNormals = normalMat.xyz;

	irisBlockId = mc_Entity.x;
	blockID = DecodeBlissBlockId(mc_Entity.x);

	int blissBlockEntityId = DecodeBlissBlockIdInt(blockEntityId);

	if(blockID == BLOCK_GROUND_WAVING_VERTICAL || blockID == BLOCK_GRASS_SHORT || blockID == BLOCK_GRASS_TALL_LOWER || blockID == BLOCK_GRASS_TALL_UPPER ) normalMat.a = 0.60;


	PORTAL = 0;
	SIGN = 0;

	#if defined WORLD && !defined HAND
		if(blissBlockEntityId == BLOCK_SIGN) SIGN = 1;

		if(blissBlockEntityId == BLOCK_END_PORTAL || blissBlockEntityId == BLOCK_END_GATEWAY) PORTAL = 1;
	#endif
	
	NameTags = 0;

#ifdef ENTITIES

	// disallow POM to work on item frames.
	if(blissEntityId == ENTITY_ITEM_FRAME) SIGN = 1;


	// try and single out nametag text and then discard nametag background
	// if( dot(gl_Color.rgb, vec3(1.0/3.0)) < 1.0) NameTags = 1;
	// if(gl_Color.a < 1.0) NameTags = 1;
	// if(gl_Color.a >= 0.24 && gl_Color.a <= 0.25 ) gl_Position = vec4(10,10,10,1);
	if(blissEntityId == ENTITY_SSS_MEDIUM || blissEntityId == ENTITY_SSS_WEAK || blissEntityId == ENTITY_PLAYER || entityId == 2468) normalMat.a = 0.45;
	
#endif

	if(blockID == BLOCK_AIR_WAVING) normalMat.a = 0.55;

    /////// ----- EMISSIVE STUFF ----- ///////
		EMISSIVE = 0.0;
		LIGHTNING = 0;
	// if(NameTags > 0) EMISSIVE = 0.9;

	HELD_ITEM_BRIGHTNESS = 0.0;
	#ifdef Hand_Held_lights
		if(DecodeBlissItemIdInt(heldItemId) > 999 || DecodeBlissItemIdInt(heldItemId2) > 999 ) HELD_ITEM_BRIGHTNESS = 0.9;
	#endif

	// normal block lightsources		
	if(blockID >= 100 && blockID < 300) EMISSIVE = 0.5;
	
	// special cases light lightning and beacon beams...	
	#ifdef ENTITIES
		if(blissEntityId == ENTITY_LIGHTNING){
			LIGHTNING = 1;
			normalMat.a = 0.50;
		}
	#endif

    /////// ----- SSS STUFF ----- ///////
		SSSAMOUNT = 0.0;

#ifdef WORLD
    /////// ----- SSS ON BLOCKS ----- ///////
	// strong
	if (
		blockID == BLOCK_SSS_STRONG || blockID == BLOCK_SAPLING || blockID == BLOCK_AIR_WAVING
	) {
		SSSAMOUNT = 1.0;
	}

	// medium
	if (
		blockID == BLOCK_GROUND_WAVING || blockID == BLOCK_GROUND_WAVING_VERTICAL
		|| blockID == BLOCK_GRASS_SHORT || blockID == BLOCK_GRASS_TALL_UPPER || blockID == BLOCK_GRASS_TALL_LOWER
	) {
		SSSAMOUNT = 0.5;
	}
	if (
		blockID == BLOCK_SSS_WEAK || blockID == BLOCK_SSS_WEAK_2 ||
		blockID == BLOCK_GLOW_LICHEN || blockID == BLOCK_SNOW_LAYERS || blockID == BLOCK_CARPET ||
		blockID == BLOCK_AMETHYST_BUD_MEDIUM || blockID == BLOCK_AMETHYST_BUD_LARGE || blockID == BLOCK_AMETHYST_CLUSTER ||
		blockID == BLOCK_BAMBOO || blockID == BLOCK_SAPLING || blockID == BLOCK_VINE
	) {
		SSSAMOUNT = 0.5;
	}
	
	// low
	#ifdef MISC_BLOCK_SSS
		if(
			blockID == BLOCK_SSS_WEIRD || blockID == BLOCK_GRASS
		){
			SSSAMOUNT = MISC_BLOCK_SSS_AMOUNT;
		}
	#endif

	#ifdef ENTITIES
		#ifdef MOB_SSS
		    /////// ----- SSS ON MOBS----- ///////
			// strong
			if(blissEntityId == ENTITY_SSS_MEDIUM) SSSAMOUNT = 0.75;
	
			// medium
	
			// low
			if(blissEntityId == ENTITY_SSS_WEAK || blissEntityId == ENTITY_PLAYER) SSSAMOUNT = 0.4;
		#endif
	#endif

	#ifdef BLOCKENTITIES
	    /////// ----- SSS ON BLOCK ENTITIES----- ///////
		// strong

		// medium
		if(blissBlockEntityId == BLOCK_SSS_WEAK_3) SSSAMOUNT = 0.4;

		// low

	#endif

   	vec3 worldpos = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz;

	#ifdef WAVY_PLANTS
		// also use normal, so up/down facing geometry does not get detatched from its model parts.
		bool InterpolateFromBase = gl_MultiTexCoord0.t < max(mc_midTexCoord.t, abs(viewToWorld(FlatNormals).y));

		if(	
			(
				// these wave off of the ground. the area connected to the ground does not wave.
				(InterpolateFromBase && (blockID == BLOCK_GRASS_TALL_LOWER || blockID == BLOCK_GROUND_WAVING || blockID == BLOCK_GRASS_SHORT || blockID == BLOCK_SAPLING || blockID == BLOCK_GROUND_WAVING_VERTICAL)) 

				// these wave off of the ceiling. the area connected to the ceiling does not wave.
				|| (!InterpolateFromBase && (blockID == 17))

				// these wave off of the air. they wave uniformly
				|| (blockID == BLOCK_GRASS_TALL_UPPER || blockID == BLOCK_AIR_WAVING)

			) && abs(position.z) < 64.0
		){
			vec3 UnalteredWorldpos = worldpos;

			// apply displacement for waving plant blocks
			worldpos += calcMovePlants(worldpos + cameraPosition) * max(lmtexcoord.w,0.5);


			// apply displacement for waving leaf blocks specifically, overwriting the other waving mode. these wave off of the air. they wave uniformly
			if(blockID == BLOCK_AIR_WAVING) worldpos = UnalteredWorldpos + calcMoveLeaves(worldpos + cameraPosition, 0.0040, 0.0064, 0.0043, 0.0035, 0.0037, 0.0041, vec3(1.0,0.2,1.0), vec3(0.5,0.1,0.5))*lmtexcoord.w;
		
		}
	#endif
	
	#ifdef PLANET_CURVATURE
		float curvature = length(worldpos) / (16*8);
		worldpos.y -= curvature*curvature * CURVATURE_AMOUNT;
	#endif

	position = mat3(gbufferModelView) * worldpos + gbufferModelView[3].xyz;
	
	// ensure hand/entities have the same transformations as the spidereyes and enchant glint programs.
	#if !defined ENTITIES && !defined HAND
		gl_Position = toClipSpace3(position);
	#endif
#endif

	#if defined Seasons && defined WORLD && !defined ENTITIES && !defined BLOCKENTITIES && !defined HAND
		YearCycleColor(vColor.rgb, gl_Color.rgb, blockID == BLOCK_AIR_WAVING, true);
	#endif

	#ifdef TAA_UPSCALING
		gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
	#endif
	#ifdef TAA
		gl_Position.xy += offsets[framemod8] * gl_Position.w*texelSize;
	#endif


#if DOF_QUALITY == 5
		vec2 jitter = clamp(jitter_offsets[frameCounter % 64], -1.0, 1.0);
		jitter = rotate(radians(float(frameCounter))) * jitter;
		jitter.y *= aspectRatio;
		jitter.x *= DOF_ANAMORPHIC_RATIO;

		#if MANUAL_FOCUS == -2
		float focusMul = 0;
		#elif MANUAL_FOCUS == -1
		float focusMul = gl_Position.z - mix(pow(512.0, screenBrightness), 512.0 * screenBrightness, 0.25);
		#else
		float focusMul = gl_Position.z - MANUAL_FOCUS;
		#endif

		vec2 totalOffset = (jitter * JITTER_STRENGTH) * focusMul * 1e-2;
		gl_Position.xy += hideGUI >= 1 ? totalOffset : vec2(0);
	#endif
}
