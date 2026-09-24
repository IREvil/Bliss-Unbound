// ===========================================================================
//  ACT / world-space reflection helpers
//
//  The voxelisation and ray-tracing files under lib/voxelization/ and
//  lib/materials/materialMethods/ were transplanted from Complementary and
//  expect a handful of small helpers that upstream defines in
//  lib/util/commonFunctions.glsl.  That file is not part of this port -- Bliss
//  has its own -- but lib/ipbr/ipbr_math.glsl already carries the same set
//  (clamp01, min1, max0, pow2, GetLuminance and friends), copied from the same
//  upstream source and include-guarded.
//
//  So this file exists purely to pull those in for the ACT path, which does not
//  otherwise include the IPBR maths.  It is deliberately not merged into
//  lib/util.glsl, which everything includes.
// ===========================================================================

#ifndef INCLUDE_ACT_COMMON
#define INCLUDE_ACT_COMMON

#include "/lib/ipbr/ipbr_math.glsl"

#endif
