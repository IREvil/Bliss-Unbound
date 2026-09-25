if (mat < 32008) {
    if (mat < 30016) {
        if (mat < 30008) {
            if (mat == 30000) { //

            } else if (mat == 30004) { //

            }
        } else {
            if (mat == 30008) { // Tinted Glass
                #ifdef CONNECTED_GLASS_EFFECT
                    uint voxelID = uint(254);
                    bool isPane = false;
                    DoConnectedGlass(colorP, color, noGeneratedNormals, playerPos, worldGeoNormal, voxelID, isPane);
                #endif
                color.a = pow(color.a, 1.0 - fresnelM);
                reflectMult = 1.0;

                #if MIRROR_TINTED_GLASS == 0
                    DoTranslucentTweaks(color, fresnelM, reflectMult, lViewPos);
                #elif MIRROR_TINTED_GLASS == 35
                    color.a = color.a * 0.65 + 0.35;
                    fresnelM = fresnelM * 0.75 + 0.25;
                    reflectMult /= color.a * 0.5 + 0.5;
                    noGeneratedNormals = true;
                #elif MIRROR_TINTED_GLASS == 70
                    color.a = color.a * 0.3 + 0.7;
                    fresnelM = fresnelM * 0.5 + 0.5;
                    reflectMult /= color.a;
                    noGeneratedNormals = true;
                #elif MIRROR_TINTED_GLASS == 100
                    color.a = 0.99;
                    fresnelM = 1.0;
                    noGeneratedNormals = true;
                #endif
            } else /*if (mat == 30012)*/ { // Slime Block
                translucentMultCalculated = true;
                reflectMult = 0.7;
                translucentMult.rgb = pow2(color.rgb) * 0.2;

                smoothnessG = color.g * 0.7;
                highlightMult = 2.5;
            }
        }
    } else {
        if (mat < 32000) {
            if (mat < 31000) {
                if (mat == 30016) { // Honey Block
                    translucentMultCalculated = true;
                    reflectMult = 1.0;
                    translucentMult.rgb = pow2(color.rgb) * 0.2;

                    smoothnessG = color.r * 0.7;
                    highlightMult = 2.5;
                } else /*if (mat == 30020)*/ { // Nether Portal
                    #ifdef SPECIAL_PORTAL_EFFECTS
                        #include "/lib/materials/specificMaterials/translucents/netherPortal.glsl"
                    #endif
                }
            } else { // (31XXX)
                if (mat % 2 == 0) { // Stained Glass
                    #ifdef CONNECTED_GLASS_EFFECT
                        uint voxelID = uint(200 + (mat - 31000) / 2);
                        bool isPane = false;
                        DoConnectedGlass(colorP, color, noGeneratedNormals, playerPos, worldGeoNormal, voxelID, isPane);
                    #endif
                    #include "/lib/materials/specificMaterials/translucents/stainedGlass.glsl"
                } else /*if (mat % 2 == 1)*/ { // Stained Glass Pane
                    #ifdef CONNECTED_GLASS_EFFECT
                        uint voxelID = uint(200 + (mat - 31000) / 2);
                        bool isPane = true;
                        DoConnectedGlass(colorP, color, noGeneratedNormals, playerPos, worldGeoNormal, voxelID, isPane);
                    #endif
                    #include "/lib/materials/specificMaterials/translucents/stainedGlass.glsl"
                    noSmoothLighting = true;
                }
            }
        } else {
            if (mat < 32004) { // Water
                #ifdef IPBR_COMPLEMENTARY_WATER
                    // le perfecto bliss: off by default so Bliss keeps its own water.
                    // Set IPBR_WATER_MATERIAL 1 to opt in.
                    #include "/lib/materials/specificMaterials/translucents/water.glsl"
                #endif
            } else /*if (mat == 32004)*/ { // Ice
                // Ice is a translucent block, so it should look like one: a see-through, glass-like surface rather
                // than a milky solid.  Upstream hands it a texture-driven smoothness and a *higher* reflection
                // multiplier than glass, and no near-field tweaks, which together read as a reflective solid.
                // These are glass' values instead -- mirror-smooth, half-strength reflections, and the same
                // close-range fade -- with the texture only deciding the last sliver of roughness so ice still
                // reads as ice rather than as a window pane.
                smoothnessG = 0.9 + 0.1 * pow2(color.g);
                highlightMult = 3.5;
                reflectMult = 0.5;

                // Thin the body.  A translucent block's opacity is its texture alpha, and ice's is high enough (and
                // the reflection contribution on top of it pushes it higher still) that it reads as opaque; capping
                // it keeps the texture's own variation -- cracks, edges, the blue cast -- while leaving the block
                // behind visible through it.  Capping rather than scaling so the intent does not depend on which
                // resource pack's ice texture is in use.
                const float ICE_MAX_ALPHA = 0.5;
                color.a = min(color.a, ICE_MAX_ALPHA);

                DoTranslucentTweaks(color, fresnelM, reflectMult, lViewPos);
            }
        }
    }
} else {
    if (mat < 32024) {
        if (mat < 32016) {
            if (mat == 32008) { // Glass
                #ifdef CONNECTED_GLASS_EFFECT
                    uint voxelID = uint(217);
                    bool isPane = false;
                    DoConnectedGlass(colorP, color, noGeneratedNormals, playerPos, worldGeoNormal, voxelID, isPane);
                #endif
                #include "/lib/materials/specificMaterials/translucents/glass.glsl"
            } else /*if (mat == 32012)*/ { // Glass Pane
                #ifdef CONNECTED_GLASS_EFFECT
                    uint voxelID = uint(218);
                    bool isPane = true;
                    DoConnectedGlass(colorP, color, noGeneratedNormals, playerPos, worldGeoNormal, voxelID, isPane);
                #endif
                if (color.a < 0.001 && abs(NdotU) > 0.95) discard; // Fixing artifacts on CTM/Opti connected glass panes
                #include "/lib/materials/specificMaterials/translucents/glass.glsl"
                noSmoothLighting = true;
            }
        } else {
            if (mat == 32016) { // Beacon
                lmCoordM.x = 0.88;

                translucentMultCalculated = true;
                translucentMult = vec4(0.0, 0.0, 0.0, 1.0);

                if (color.b > 0.5) {
                    if (color.g - color.b < 0.01 && color.g < 0.99) {
                        #include "/lib/materials/specificMaterials/translucents/glass.glsl"
                    } else { // Beacon:Center
                        lmCoordM = vec2(0.0);
                        noDirectionalShading = true;

                        float lColor = length(color.rgb);
                        vec3 baseColor = vec3(0.1, 1.0, 0.92);
                        if (lColor > 1.65)      color.rgb = baseColor + 0.2;
                        else if (lColor > 1.5)  color.rgb = baseColor + 0.15;
                        else if (lColor > 1.3)  color.rgb = baseColor + 0.08;
                        else if (lColor > 1.15) color.rgb = baseColor + 0.035;
                        else                    color.rgb = baseColor;
                        emission = 3.5;
                    }
                } else { // Beacon:Obsidian
                    float factor = color.r * 1.5;

                    smoothnessG = factor;
                    highlightMult = 2.0 + min1(smoothnessG * 2.0) * 1.5;
                    smoothnessG = min1(smoothnessG);
                }

            } else /*if (mat == 32020)*/ { //

            }
        }
    } else {
        if (mat < 32032) {
            if (mat == 32024) { //

            } else /*if (mat == 32028)*/ { //

            }
        } else {
            if (mat == 32032) { //

            } else /*if (mat == 32036)*/ { //

            }
        }
    }
}
