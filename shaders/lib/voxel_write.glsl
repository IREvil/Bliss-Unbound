ivec3 GetVoxelIndex(const in vec3 playerPos) {
	vec3 cameraOffset = fract(cameraPosition);
	return ivec3(floor(playerPos + cameraOffset) + VoxelSize3/2u);
}

void SetVoxelBlock(const in vec3 playerPos, const in uint blockId) {
	ivec3 voxelPos = GetVoxelIndex(playerPos);
	if (clamp(voxelPos, ivec3(0), ivec3(VoxelSize-1u)) != voxelPos) return;

	imageStore(imgVoxelMask, voxelPos, uvec4(blockId));
}

void PopulateShadowVoxel(const in vec3 playerPos) {
	uint voxelId = 0u;
	vec3 originPos = playerPos;

	if (
		renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT ||
		renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED
	) {
		// Iris' id is Complementary-ordered; the voxel buffer is read back with
		// Bliss' BLOCK_* ranges, so translate it first.
		float decodedId = DecodeBlissBlockId(mc_Entity.x);
		voxelId = decodedId < 0.0 ? 0u : uint(decodedId + 0.5);

		#ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
			if (voxelId == 0u && at_midBlock.w > 0) voxelId = uint(BLOCK_LIGHT_1 + at_midBlock.w - 1);
		#endif

		if (voxelId == 0u) voxelId = 1u;

		originPos += at_midBlock.xyz/64.0;
	}
	
	#ifdef LPV_ENTITY_LIGHTS
		if (
			((renderStage == MC_RENDER_STAGE_ENTITIES && (currentRenderedItemId > 0 || entityId > 0)) || renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES)
		) {
			// Iris ids are Complementary-ordered here (entity.properties and
			// item.properties list Complementary last), so translate them back
			// to the ranges this buffer is read with.
			int blissEntity = DecodeBlissEntityIdInt(entityId);
			int blissItem = DecodeBlissItemIdInt(currentRenderedItemId);
			int blissBlockEntity = DecodeBlissBlockIdInt(blockEntityId);

			if (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES) {
				if (blissBlockEntity > 0 && blissBlockEntity < 500)
					voxelId = uint(blissBlockEntity);
			}
			else if (blissItem > 0 && blissItem < 1200 && entityId > 0) {
				// entityId > 0 is what separates a DROPPED item from a HELD one.
				//
				// A held item is drawn without an entity id, so the exclusion below
				// never matched it: blissEntity was 0 rather than ENTITY_PLAYER and
				// the guard passed.  The item was then voxelised as if it had been
				// PLACED at the player's own position -- a torch's worth of light
				// centred on the body, which is why the player read as a torch.
				//
				// A held light belongs to the handheld path (GetHandLight), which
				// puts it in front of the player and moves with them.  Dropped items
				// still light the world, because those do carry an entity id.
				if (blissEntity != ENTITY_ITEM_FRAME && blissEntity != ENTITY_PLAYER)
					voxelId = uint(blissItem);
			}
			else {
				switch (blissEntity) {
					case ENTITY_BLAZE:
					case ENTITY_END_CRYSTAL:
					// case ENTITY_FIREBALL_SMALL:
					case ENTITY_GLOW_SQUID:
					case ENTITY_MAGMA_CUBE:
					case ENTITY_SPECTRAL_ARROW:
					case ENTITY_TNT:
						voxelId = uint(blissEntity);
						break;
				}
			}
		}
	#endif

	if (voxelId > 0u)
		SetVoxelBlock(originPos, voxelId);
}