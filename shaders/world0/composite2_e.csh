#version 430 compatibility

// Vertical pass of the rough-reflection blur, at REFLECTION_RES_WORLD; runs after composite2_d and before
// composite2 (the lighting pass), which blends the result in for rough surfaces.
#define OVERWORLD_SHADER
#define PLAYER_REF_TRACE
#define REFL_PREPASS_AVAILABLE
#define REFL_PREPASS 5

#include "/dimensions/composite1.fsh"
