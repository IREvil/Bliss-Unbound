#define RENDER_SHADOWCOMP

layout (local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

// Complementary's ACT floodfill takes over this pass when it is enabled.  It is
// the same kind of work as Bliss' LPV floodfill below -- spreading light through
// a voxel volume -- which is why the two are mutually exclusive rather than
// sharing the pass: IS_LPV_ENABLED is switched off by settings.glsl whenever
// COLORED_LIGHTING_INTERNAL > 0.
#if COLORED_LIGHTING_INTERNAL > 0
    layout(rgba16f) uniform writeonly image3D floodfill_img;
    layout(rgba16f) uniform writeonly image3D floodfill_img_copy;

    // lightVoxelization.glsl comes in via actFloodfill.glsl for the volume
    // layout and the voxel read helpers, and it expects these from its host --
    // the same set the shadow programs supply.
    uniform usampler3D voxel_sampler;
    // voxel_sampler reads back all zeros in this pass (verified in game); imageLoad sees the ids.
    layout(r16ui) uniform readonly uimage3D voxel_img;
    #define ACT_VOXEL_IMAGE_READ
    uniform int framemod2;
    uniform vec3 cameraPosition;
    uniform vec3 previousCameraPosition;
    // Used by the behind-player optimisation, which needs the view direction.
    uniform mat4 gbufferProjectionInverse;
    uniform mat4 gbufferModelViewInverse;
    // fract(cameraPosition) rather than Iris' cameraPositionFract, which is not
    // declared in every program this has to compile in.
    vec3 cameraPositionBestFract = fract(cameraPosition);

    #define OPTIMIZATION_ACT_BEHIND_PLAYER
    #define OPTIMIZATION_ACT_HALF_RATE_SPREADING
    //#define OPTIMIZATION_ACT_SHARED_MEMORY

    #include "/lib/voxelization/act_common.glsl"
    #include "/lib/voxelization/actFloodfill.glsl"

    // Iris parses `workGroups` as a directive and requires a literal ivec3
    // constructor, so this cannot be a reference or an expression -- it has to
    // be one of these.  The sizes are exactly those ACT_DISTANCE can produce
    // (chunks x 16), and the values are upstream's formula
    // ivec3(N/8, min(N/16, 32), N/8), verified against Complementary's own
    // 128..1024 table.
    #if   COLORED_LIGHTING_INTERNAL == 64
        const ivec3 workGroups = ivec3(8, 4, 8);
    #elif COLORED_LIGHTING_INTERNAL == 96
        const ivec3 workGroups = ivec3(12, 6, 12);
    #elif COLORED_LIGHTING_INTERNAL == 128
        const ivec3 workGroups = ivec3(16, 8, 16);
    #elif COLORED_LIGHTING_INTERNAL == 160
        const ivec3 workGroups = ivec3(20, 10, 20);
    #elif COLORED_LIGHTING_INTERNAL == 192
        const ivec3 workGroups = ivec3(24, 12, 24);
    #elif COLORED_LIGHTING_INTERNAL == 256
        const ivec3 workGroups = ivec3(32, 16, 32);
    #elif COLORED_LIGHTING_INTERNAL == 320
        const ivec3 workGroups = ivec3(40, 20, 40);
    #elif COLORED_LIGHTING_INTERNAL == 384
        const ivec3 workGroups = ivec3(48, 24, 48);
    #elif COLORED_LIGHTING_INTERNAL == 448
        const ivec3 workGroups = ivec3(56, 28, 56);
    #elif COLORED_LIGHTING_INTERNAL == 512
        const ivec3 workGroups = ivec3(64, 32, 64);
    #else
        const ivec3 workGroups = ivec3(16, 8, 16);
    #endif

    void main() { DoActFloodfill(); }
#else

#if   LPV_SIZE == 8
    const ivec3 workGroups = ivec3(32, 32, 32);
#elif LPV_SIZE == 7
    const ivec3 workGroups = ivec3(16, 16, 16);
#elif LPV_SIZE == 6
    const ivec3 workGroups = ivec3(8, 8, 8);
#endif

#ifdef IS_LPV_ENABLED
    shared vec4 lpvSharedData[10*10*10];
    shared uint voxelSharedData[10*10*10];

    const vec2 LpvBlockSkyFalloff = vec2(0.96, 0.96);
    const ivec3 lpvFlatten = ivec3(1, 10, 100);

    uniform int frameCounter;
    uniform vec3 cameraPosition;
    uniform vec3 previousCameraPosition;

    #include "/lib/hsv.glsl"
    #include "/lib/util.glsl"
    #include "/lib/blocks.glsl"
    #include "/lib/lpv_common.glsl"
    #include "/lib/lpv_blocks.glsl"
    #include "/lib/lpv_buffer.glsl"
    #include "/lib/voxel_common.glsl"

    int sumOf(ivec3 vec) {return vec.x + vec.y + vec.z;}

    int getSharedIndex(ivec3 pos) {
        return sumOf(pos * lpvFlatten);
    }

    vec4 GetLpvValue(in ivec3 texCoord) {
        if (clamp(texCoord, ivec3(0), ivec3(LpvSize) - 1) != texCoord) return vec4(0.0);

        vec4 lpvSample = (frameCounter % 2) == 0
            ? imageLoad(imgLpv2, texCoord)
            : imageLoad(imgLpv1, texCoord);

        vec4 hsv_sky = vec4(RgbToHsv(lpvSample.rgb), lpvSample.a);
        hsv_sky.zw = exp2(hsv_sky.zw * LpvBlockSkyRange) - 1.0;
        lpvSample = vec4(HsvToRgb(hsv_sky.xyz), hsv_sky.w);

        return lpvSample;
    }
    
    uint GetVoxelBlock(const in ivec3 voxelPos) {
        if (clamp(voxelPos, ivec3(0), ivec3(VoxelSize3-1u)) != voxelPos)
            return BLOCK_EMPTY;
        
        return imageLoad(imgVoxelMask, voxelPos).r;
    }

    void PopulateSharedIndex(const in ivec3 imgCoordOffset, const in ivec3 workGroupOffset, const in uint i) {
        ivec3 pos = workGroupOffset + ivec3(i / lpvFlatten) % 10;

        lpvSharedData[i] = GetLpvValue(imgCoordOffset + pos);
        voxelSharedData[i] = GetVoxelBlock(pos);
    }

    vec4 sampleShared(ivec3 pos, int mask_index) {
        int shared_index = getSharedIndex(pos + 1);

        float mixWeight = 1.0;
        uint mask = 0xFFFF;
        uint blockId = voxelSharedData[shared_index];
        
        if (blockId > 0 && blockId != BLOCK_EMPTY) {
            uvec2 blockData = imageLoad(imgBlockData, int(blockId)).rg;
            mask = (blockData.g >> 24) & 0xFFFF;
        }

        return lpvSharedData[shared_index] * ((mask >> mask_index) & 1u);
    }

    vec4 mixNeighbours(const in ivec3 fragCoord, const in uint mask) {
        uvec3 m1 = (uvec3(mask) >> uvec3(0, 2, 4)) & uvec3(1u);
        uvec3 m2 = (uvec3(mask) >> uvec3(1, 3, 5)) & uvec3(1u);

        vec4 sX1 = sampleShared(fragCoord + ivec3(-1,  0,  0), 1) * m1.x;
        vec4 sX2 = sampleShared(fragCoord + ivec3( 1,  0,  0), 0) * m2.x;
        vec4 sY1 = sampleShared(fragCoord + ivec3( 0, -1,  0), 3) * m1.y;
        vec4 sY2 = sampleShared(fragCoord + ivec3( 0,  1,  0), 2) * m2.y;
        vec4 sZ1 = sampleShared(fragCoord + ivec3( 0,  0, -1), 5) * m1.z;
        vec4 sZ2 = sampleShared(fragCoord + ivec3( 0,  0,  1), 4) * m2.z;

        const vec4 avgFalloff = (1.0/6.0) * LpvBlockSkyFalloff.xxxy;
        return (sX1 + sX2 + sY1 + sY2 + sZ1 + sZ2) * avgFalloff;
    }
#endif


////////////////////////////// VOID MAIN //////////////////////////////

void main() {
    #ifdef IS_LPV_ENABLED
        uvec3 chunkPos = gl_WorkGroupID * gl_WorkGroupSize;
        if (any(greaterThanEqual(chunkPos, LpvSize3))) return;

        // Pre-populate shared-memory buffer for improved sampling performance
        uint i = uint(gl_LocalInvocationIndex) * 2u;
        if (i < 1000u) {
            ivec3 imgCoordOffset = ivec3(floor(cameraPosition) - floor(previousCameraPosition));
            ivec3 workGroupOffset = ivec3(gl_WorkGroupID * gl_WorkGroupSize) - 1;

            PopulateSharedIndex(imgCoordOffset, workGroupOffset, i);
            PopulateSharedIndex(imgCoordOffset, workGroupOffset, i + 1u);
        }

        barrier();

        // Exit early if outside LPV buffer size
        ivec3 imgCoord = ivec3(gl_GlobalInvocationID);
        if (any(greaterThanEqual(imgCoord, LpvSize3))) return;

        vec4 lightValue = vec4(0.0);
        vec3 lightColor = vec3(0.0);
        vec3 tintColor = vec3(1.0);
        float lightRange = 0.0;
        uint mixMask = 0xFFFF;
    
        // Decode light data for current voxel
        uint blockId = voxelSharedData[getSharedIndex(ivec3(gl_LocalInvocationID) + 1)];

        if (blockId > 0u) {
            uvec2 blockData = imageLoad(imgBlockData, int(blockId)).rg;
            vec4 lightColorRange = unpackUnorm4x8(blockData.r);
            lightColor = srgbToLinear(lightColorRange.rgb);
            lightRange = lightColorRange.a * 255.0;
            vec4 tintColorMask = unpackUnorm4x8(blockData.g);
            tintColor = srgbToLinear(tintColorMask.rgb);
            mixMask = (blockData.g >> 24) & 0xFFFF;
        }

        // Mix neighbor voxel light values
        if (any(greaterThan(tintColor, vec3(0.0)))) {
            vec4 lightMixed = mixNeighbours(ivec3(gl_LocalInvocationID), mixMask);
            lightMixed.rgb *= tintColor;
            lightValue += lightMixed;
        }

        // Add light for current voxel
        if (lightRange > 0.0) {
            vec3 hsv = RgbToHsv(lightColor);
            hsv.z = exp2(lightRange) - 1.0;
            lightValue.rgb += HsvToRgb(hsv);
        }

        // Convert back to linear RGB space
        vec4 hsv_sky = vec4(RgbToHsv(lightValue.rgb), lightValue.a);
        hsv_sky.zw = log2(hsv_sky.zw + 1.0) / LpvBlockSkyRange;
        lightValue = vec4(HsvToRgb(hsv_sky.xyz), hsv_sky.w);

        // Store final value
        if (frameCounter % 2 == 0)
            imageStore(imgLpv1, imgCoord, lightValue);
        else
            imageStore(imgLpv2, imgCoord, lightValue);
    #endif
}

#endif // COLORED_LIGHTING_INTERNAL > 0
