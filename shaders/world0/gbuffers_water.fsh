#version 130

#define OVERWORLD_SHADER
#define WSR_TRANSLUCENT
// Pairs with world0's shadow pass, which records the player's quads.
#define PLAYER_REF_TRACE

#include "/dimensions/all_translucent.fsh"