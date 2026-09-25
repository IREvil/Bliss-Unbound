#version 430 compatibility

// Horizontal pass of the rough-reflection blur, at REFLECTION_RES_WORLD; runs after composite2_a (the trace) and
// before composite2_e (the vertical pass) and composite2 (the lighting pass).
#define OVERWORLD_SHADER
#define PLAYER_REF_TRACE
#define REFL_PREPASS_AVAILABLE
#define REFL_PREPASS 4

#include "/dimensions/composite1.fsh"
