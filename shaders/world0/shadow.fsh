#version 120

#include "/lib/settings.glsl"

varying vec4 color;

varying vec2 texcoord;
uniform sampler2D tex;
uniform sampler2D noisetex;
#ifdef CONNECTED_GLASS_EFFECT
	varying vec2 shadowCGSprite;
#endif

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

float blueNoise(){
  return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 );
}


void main() {
	vec2 shadowUV = texcoord.xy;
	#ifdef CONNECTED_GLASS_EFFECT
		// Complementary's DoSimpleConnectedGlass: one texel off the sprite centre.
		if (shadowCGSprite.x > 0.0) shadowUV = (floor(shadowUV / shadowCGSprite) + 0.4375) * shadowCGSprite;
	#endif
	
	vec4 shadowColor = vec4(texture2D(tex,shadowUV).rgb * color.rgb,  texture2DLod(tex, shadowUV, 0).a);

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		if(shadowColor.a > 0.9999) shadowColor.rgb = vec3(0.0);
	#endif

	gl_FragData[0] = shadowColor;

	// gl_FragData[0] = vec4(texture2D(tex,texcoord.xy).rgb * color.rgb,  texture2DLod(tex, texcoord.xy, 0).a);

  	#ifdef Stochastic_Transparent_Shadows
		if(gl_FragData[0].a < blueNoise()) { discard; return;}
  	#endif
}
