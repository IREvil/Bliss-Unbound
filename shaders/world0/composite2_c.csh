#version 430 compatibility

// Horizontal pass of the rough-reflection blur, at REFLECTION_RES_WORLD; runs after composite2_a (the trace) and
// before composite2_d (the vertical pass) and composite2 (the lighting pass).
//
// The name matters: Iris collects a program's compute passes as composite2_a.csh, _b.csh, _c.csh and STOPS AT THE
// FIRST MISSING LETTER, so this has to stay _c with _a/_b present and _d directly after it. A gap silently drops
// every later pass.
#define OVERWORLD_SHADER
#define PLAYER_REF_TRACE
#define REFL_PREPASS_AVAILABLE
#define REFL_PREPASS 3

#include "/dimensions/composite1.fsh"
