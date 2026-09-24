#version 130

#define OVERWORLD_SHADER
// Only this entry pairs with world0's shadow pass (which writes the player's quads) and composite3 (which clears them).
#define PLAYER_REF_TRACE
// Its reflections are traced beforehand at reduced resolution by composite2_a/_b.csh.
#define REFL_PREPASS_AVAILABLE

#include "/dimensions/composite1.fsh"