#version 430 compatibility

// Temporal accumulation of the block reflections traced by composite2_a.csh.
#define OVERWORLD_SHADER
#define PLAYER_REF_TRACE
#define REFL_PREPASS_AVAILABLE
#define REFL_PREPASS 3

#include "/dimensions/composite1.fsh"
