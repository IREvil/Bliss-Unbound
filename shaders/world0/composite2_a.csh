#version 430 compatibility

// Reflection prepass for opaque blocks, at REFLECTION_RES_WORLD; runs before composite2 (the lighting pass).
#define OVERWORLD_SHADER
#define PLAYER_REF_TRACE
#define REFL_PREPASS_AVAILABLE
#define REFL_PREPASS 1

#include "/dimensions/composite1.fsh"
