#version 430 compatibility

// Reflection prepass for water and glass, at REFLECTION_RES_MIRROR; runs before composite2 (the lighting pass).
#define OVERWORLD_SHADER
#define PLAYER_REF_TRACE
#define REFL_PREPASS_AVAILABLE
#define REFL_PREPASS 2

#include "/dimensions/composite1.fsh"
