#version 130

#define OVERWORLD_SHADER
// Only this entry pairs with world0's shadow pass (which writes the player's quads) and composite3 (which clears them).
#define PLAYER_REF_TRACE

#include "/dimensions/composite1.fsh"