// ===========================================================================
//  Block / entity / item id translation
//
//  The merged .properties libraries give `mc_Entity.x` Complementary's
//  numbering (integratedPBR+ needs it verbatim), while Bliss' own systems are
//  written against its own BLOCK_*/ENTITY_*/ITEM_* constants.  These helpers
//  bridge the two.
//
//  The fallback matters: a block that only Bliss knows keeps its own id, and a
//  Complementary id with no Bliss counterpart stays as it is (so it simply
//  matches no Bliss constant, which is the correct outcome).
// ===========================================================================

#ifndef IPBR_ID_DECODE_INCLUDED
#define IPBR_ID_DECODE_INCLUDED

#include "/lib/ipbr/id_maps.glsl"

// Hand exceptions on top of the generated map.  Packed/blue ice sit in Bliss' strong-SSS bucket, which makes
// the opaque blocks glow; integratedPBR+ gives them intense fresnel instead, so they get no Bliss category.
int BlissBlockIdFromMatPatched(int id) {
	if (id == 10384 || id == 10388) return 0;
	return BlissBlockIdFromMat(id);
}

float DecodeBlissBlockId(float irisId) {
	int rawId = irisId < -0.5 ? -1 : int(irisId + 0.5);
	int mapped = BlissBlockIdFromMatPatched(rawId);
	return float(mapped != 0 ? mapped : rawId);
}

int DecodeBlissBlockIdInt(int rawId) {
	int mapped = BlissBlockIdFromMatPatched(rawId);
	return mapped != 0 ? mapped : rawId;
}

int DecodeBlissEntityIdInt(int rawId) {
	int mapped = BlissEntityIdFromIris(rawId);
	return mapped != 0 ? mapped : rawId;
}

int DecodeBlissItemIdInt(int rawId) {
	int mapped = BlissItemIdFromIris(rawId);
	// Unmapped Complementary items (air 40008, tools 45xxx) are not light sources.
	if (mapped == 0 && rawId >= 40000) return 0;
	return mapped != 0 ? mapped : rawId;
}

#endif // IPBR_ID_DECODE_INCLUDED
