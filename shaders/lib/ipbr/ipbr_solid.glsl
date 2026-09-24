// ===========================================================================
//  IntegratedPBR+ -- solid path
//
//  Included from /dimensions/all_solid.fsh *inside* main(), after the albedo
//  has been sampled.  It fills in the environment declared in ipbr_globals.glsl
//  and then runs Complementary's material database.
//
//  On the way out these globals hold the result and are consumed by the
//  G-buffer write further down in all_solid.fsh:
//      smoothnessG    perceptual smoothness       -> colortex8.r
//      highlightMult  specular highlight scale    -> colortex8.g (as F0)
//      materialMask   material tags               -> LabPBR metal selection
//      subsurfaceMode 0 / 1 / 2 / 3               -> colortex8.b
//      emission       emissive strength           -> colortex8.a
// ===========================================================================

#ifdef IPBR

    // ---- texture colour, Complementary's naming ----
    glColorRaw = vColor;
    glColor = vColor;
    color = Albedo;         // all_solid.fsh already applied the vertex colour
    colorP = ipbrTexSample.rgb;   // texture colour before the vertex colour

    // ---- texture coordinates ----
    // Bliss never stores midCoord/absMidCoordPos directly, but vtexcoordam
    // encodes them exactly:  .pq = 2 * |texCoord - midCoord|
    //                        .st = midCoord - |texCoord - midCoord|
    absMidCoordPos = vtexcoordam.pq * 0.5;
    midCoord = vtexcoordam.st + absMidCoordPos;
    signMidCoordPos = sign(texCoord - midCoord);

    // ---- lightmap ----
    lmCoord = lmtexcoord.zw;
    lmCoordM = lmCoord;

    // ---- positions and normals ----
    viewPos = fragpos;
    nViewPos = normalize(fragpos);
    lViewPos = length(fragpos);
    playerPos = playerpos;
    normalM = normal;
    geoNormal = normal;
    worldGeoNormal = normalize(viewToWorld(geoNormal));
    shadowMult = vec3(1.0);

    // ---- world orientation ----
    upVec = normalize(gbufferModelView[1].xyz);
    eastVec = normalize(gbufferModelView[0].xyz);
    northVec = normalize(gbufferModelView[2].xyz);
    sunVec = normalize(sunPosition);
    SdotU = dot(sunVec, upVec);
    NdotU = dot(normalM, upVec);
    geoNdotU = NdotU;
    NdotUmax0 = max(NdotU, 0.0);
    sunFactor = SdotU < 0.0
        ? clamp(SdotU + 0.375, 0.0, 0.75) / 0.75
        : clamp(SdotU + 0.03125, 0.0, 0.0625) / 0.0625;
    sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
    sunVisibility2 = sunVisibility * sunVisibility;
    shadowTimeVar1 = abs(sunVisibility - 0.5) * 2.0;
    shadowTimeVar2 = shadowTimeVar1 * shadowTimeVar1;
    shadowTime = shadowTimeVar2 * shadowTimeVar2;
    // Complementary derives these from timeAngle; the sun's elevation above the
    // world horizon is the same quantity and is what the effects actually use.
    noonFactorRaw = max(SdotU, 0.0);
    noonFactor = sqrt(noonFactorRaw);
    invNoonFactor = 1.0 - noonFactor;
    nightFactor = max(-SdotU, 0.0);
    invNightFactor = 1.0 - nightFactor;
    lightVec = sunVec * (SdotU < 0.0 ? -1.0 : 1.0);

    // ---- weather and eye state ----
    rainFactor = rainStrength;
    rainFactor2 = rainFactor * rainFactor;
    invRainFactor = 1.0 - rainFactor;
    inRainy = rainStrength;
    inSnowy = 0.0;
    eyeBrightnessM = float(eyeBrightnessSmooth.y) / 240.0;
    eyeBrightnessM2 = eyeBrightnessSmooth.y > 239 ? 1.0 : 0.0;

    // ---- dither ----
    dither = Bayer64(gl_FragCoord.xy);
    #ifdef TAA
        dither = fract(dither + goldenRatio * mod(float(frameCounter), 3600.0));
    #endif

    // ---- material state defaults, matching Complementary's per-program ones ----
    mat = int(irisBlockId < -0.5 ? -1.0 : irisBlockId + 0.5);
    noSmoothLighting = false;
    noDirectionalShading = false;
    noVanillaAO = false;
    centerShadowBias = false;
    noGeneratedNormals = false;
    doTileRandomisation = true;
    subsurfaceMode = 0;
    smoothnessG = 0.0;
    smoothnessD = 0.0;
    highlightMult = 1.0;
    emission = 0.0;
    noiseFactor = 1.0;
    snowFactor = 1.0;
    snowMinNdotU = 0.0;
    noPuddles = 0.0;
    maRecolor = vec3(0.0);

    #if defined GBUFFERS_ENTITIES || defined GBUFFERS_HAND
        materialMask = OSIEBCA * 254.0;             // No SSAO, No TAA, Reduce Reflection
        noSmoothLighting = atlasSize.x < 600.0;     // Stops fire looking too dim
        noiseFactor = 0.75;
    #else
        materialMask = 0.0;
    #endif

    // ---- texture-space tangent basis and mip level ----
    // Derived from Bliss' own dcdx/dcdy (all_solid.fsh computes them at file
    // scope with its mip bias), so Complementary's lib/util/miplevel.glsl is
    // not included and cannot redeclare them.
    midCoordPos = absMidCoordPos * signMidCoordPos;
    // GenerateNormals takes its sample offset as `16.0 / atlasSizeM`, then
    // divides by GENERATED_NORMAL_RES.
    //
    // Complementary resolves atlasSizeM in lib/util/miplevel.glsl:
    //     vec2 atlasSizeM = atlasSize;
    // with a `textureSize(tex, 0)` fallback when atlasSize is unusable.  In this
    // host atlasSize comes through unusable, so query the sampler directly --
    // textureSize cannot be zero, stale or NaN, and it is the real atlas size in
    // pixels, which is what the expression wants.
    vec2 ipbrAtlasSize = vec2(textureSize(tex, 0));
    if (!(ipbrAtlasSize.x > 64.0 && ipbrAtlasSize.y > 64.0)) {
        ipbrAtlasSize = vec2(1024.0);   // 16px sprites in a 1024 atlas
    }
    // Upstream's value: `offsetR = 16.0 / atlasSize / GENERATED_NORMAL_RES`,
    // which resolves to 0.125 texture texels at the default resolution of 128.
    //
    // This was briefly scaled up so the step landed on a full texel, because
    // nothing registered at a fraction of one.  That was a workaround for a
    // symptom whose real cause was elsewhere -- a shadowed tbnMatrix, which made
    // the result NaN and got silently discarded.  With that fixed the upstream
    // step works, and the larger step is actively harmful: it multiplies every
    // gradient by 8, so normalMap.xy saturates against the +-1 clamp, the
    // perturbation reaches ~45 degrees, and surfaces flip away from the light
    // (large shifting black areas) while GENERATED_NORMAL_MULT stops having any
    // visible effect because the value is already clamped.
    atlasSizeM = ipbrAtlasSize;
    ipbrAtlasSizeDebug = ipbrAtlasSize;
    // GenerateNormals runs inside material branches, where derivatives are undefined.
    ipbrTexCoordFwidth = fwidth(texCoord);
    {
        // Complementary divides the screen-space UV derivatives by the sprite's
        // half-size to get texels-per-pixel, then takes log2 of that for the mip
        // level CoatTextures samples its noise texture at.
        //
        // absMidCoordPos reads as ZERO in this host (the same vtexcoordam problem
        // that collapsed the generated-normal sprite bounds), so the divisor fell
        // through to the 1e-5 guard, mipx became enormous and miplevel saturated.
        // textureLod(noiseTex, noiseCoord, <huge mip>) then samples the smallest
        // level of the noise texture -- a coarse pattern laid over every surface
        // the table gives a noiseFactor to, i.e. grass and leaves.  That is the
        // "mesh", and it is independent of both generated-normal sliders because
        // CoatTextures scales the albedo, not the normal.
        //
        // Fall back to half a 16px sprite (8 texels), which is what absMidCoordPos holds upstream;
        // one texel made miplevel 3 too high and faded coated textures out entirely.
        vec2 ipbrMidSafe = max(absMidCoordPos, 8.0 / max(ipbrAtlasSize, vec2(1.0)));
        vec2 mipx = dcdx / ipbrMidSafe * 8.0;
        vec2 mipy = dcdy / ipbrMidSafe * 8.0;
        miplevel = max(0.5 * log2(max(dot(mipx, mipx), dot(mipy, mipy))), 0.0);
    }
    #ifdef IPBR_NEEDS_TANGENT
        // Build the tangent basis the generated-normal / coated-texture code
        // samples against.  `at_tangent` is normally supplied by Iris, but it is
        // not part of Minecraft's own terrain vertex format, so if it ever comes
        // Build the basis deterministically from the geometric normal.
        //
        // `at_tangent` is NOT part of Minecraft's terrain vertex format -- Iris
        // only supplies it when a shader asks for it, and if it arrives as zero
        // then `normalize()` of it is NaN.  A NaN tangent poisons tbnMatrix,
        // which makes `normalize(normalMap * tbnMatrix)` NaN, which the final
        // normal guard then replaces with the geometric normal -- so generated
        // normals silently render as if they did nothing at all.  Every
        // derivative-based fallback still routes through the same poisoned
        // input, so the basis is derived from `normal` alone here: it cannot be
        // NaN, and it makes the failure mode impossible rather than masked.
        // Prefer the vertex tangent (Interpolated from at_tangent in the vertex
        // stage, exactly as Complementary uses it).  It is stable at every
        // viewing angle.  The derivative reconstruction below is only a
        // fallback: at grazing angles dFdx(texCoord) collapses, the determinant
        // goes ill-conditioned, and the reconstructed tangent swings to an
        // arbitrary direction, which rotates the relief axes and shows up as a
        // mesh that flips between black and white as the camera turns.
        vec3 ipbrN = normalize(normal);
        // ------------------------------------------------------------------
        // TEMPORARY TEST -- bypass the interpolated tangent.
        //
        // The mesh survives with GenerateNormals' output forced to a constant,
        // so it is not produced by the normal.  GN turns on exactly one other
        // thing: IPBR_NEEDS_TANGENT, i.e. the at_tangent read and the 	angent
        // varying.  The matrix this block builds is read only by GenerateNormals,
        // which was returning early during that test -- so the matrix was unused
        // and the mesh still appeared.
        //
        // That leaves the varying itself.  Using a fixed vector here keeps the
        // relief working while removing any dependence on it:
        //
        //   mesh disappears -> the tangent attribute read / varying is the cause
        //   mesh remains    -> it is something else in this block, and the
        //                      tangent path can be excluded too
        // ------------------------------------------------------------------
        vec3 ipbrT = tangent.rgb;
        vec3 ipbrB;
        float ipbrT2 = dot(ipbrT, ipbrT);

        if (ipbrT2 > 0.5) {
            ipbrT *= inversesqrt(ipbrT2);
            // Complementary multiplies by tangent.w for handedness, but w may be
            // zero if at_tangent is only partially supplied in this host -- the
            // same category of problem as absMidCoordPos reading zero.  Scaling
            // the cross product by zero yields a zero vector, and the guard below
            // cannot recover it (scaling zero by anything is still zero), leaving a
            // degenerate non-orthonormal basis.  Default to +1 when w is unusable.
            float ipbrW = abs(tangent.w) > 0.5 ? sign(tangent.w) : 1.0;
            ipbrB = cross(ipbrT, ipbrN) * ipbrW;   // Complementary's handedness
        } else {
            vec3 ipbrDPdx = dFdx(fragpos);
            vec3 ipbrDPdy = dFdy(fragpos);
            vec2 ipbrDUdx = dFdx(texCoord);
            vec2 ipbrDUdy = dFdy(texCoord);

            float ipbrDet = ipbrDUdx.x * ipbrDUdy.y - ipbrDUdy.x * ipbrDUdx.y;
            if (abs(ipbrDet) > 1e-9) {
                float ipbrInvDet = 1.0 / ipbrDet;
                ipbrT = (ipbrDPdx * ipbrDUdy.y - ipbrDPdy * ipbrDUdx.y) * ipbrInvDet;
                ipbrB = (ipbrDPdy * ipbrDUdx.x - ipbrDPdx * ipbrDUdy.x) * ipbrInvDet;
            } else {
                vec3 ipbrHelper = abs(ipbrN.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
                ipbrT = cross(ipbrHelper, ipbrN);
                ipbrB = cross(ipbrT, ipbrN);
            }

            // Orthonormalise; if the reconstruction collapsed, fall back to any
            // rigid basis rather than propagating a degenerate one.
            ipbrT -= ipbrN * dot(ipbrN, ipbrT);
            float ipbrFb2 = dot(ipbrT, ipbrT);
            if (!(ipbrFb2 > 1e-6)) {
                vec3 ipbrHelper = abs(ipbrN.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
                ipbrT = cross(ipbrHelper, ipbrN);
                ipbrFb2 = dot(ipbrT, ipbrT);
            }
            ipbrT *= inversesqrt(max(ipbrFb2, 1e-20));
            ipbrB = cross(ipbrT, ipbrN);
        }

        ipbrB *= inversesqrt(max(dot(ipbrB, ipbrB), 1e-20));
        ipbrTbnMatrix = mat3(ipbrT, ipbrB, ipbrN);
    #endif

    // ---- run the database ----
    #ifdef GBUFFERS_TERRAIN
        #include "/lib/materials/materialHandling/terrainMaterials.glsl"
    #elif defined GBUFFERS_ENTITIES
        #ifdef IS_IRIS
            if (currentRenderedItemId == 0) {
                #include "/lib/materials/materialHandling/entityIPBR.glsl"
            } else {
                #include "/lib/materials/materialHandling/irisIPBR.glsl"
            }
        #else
            #include "/lib/materials/materialHandling/entityIPBR.glsl"
        #endif

        if (materialMask != OSIEBCA * 254.0) materialMask += OSIEBCA * 100.0;
    #elif defined GBUFFERS_HAND
        #ifdef IS_IRIS
            #include "/lib/materials/materialHandling/irisIPBR.glsl"
            if (materialMask != OSIEBCA * 254.0) materialMask += OSIEBCA * 100.0;
        #endif
    #elif defined GBUFFERS_BLOCK
        #include "/lib/materials/materialHandling/blockEntityIPBR.glsl"
    #endif

    // terrainMaterials.glsl already applies this for terrain
    #if IPBR_EMISSIVE_MODE != 1 && !defined GBUFFERS_TERRAIN
        emission = GetCustomEmissionForIPBR(color, glColor, emission);
    #endif

    // Complementary applies these straight after the material table.  The
    // terrain path already does it inside terrainMaterials.glsl, so only the
    // entity/hand/block paths call them here.
    #ifndef GBUFFERS_TERRAIN
        #ifdef GENERATED_NORMALS
            // Same collapsed-bounds problem as the terrain path; see the note in
            // terrainMaterials.glsl.
            if (!noGeneratedNormals) {
                vec2 ipbrSavedAbsMidCoordPos = absMidCoordPos;
                vec2 ipbrSavedMidCoordPos = midCoordPos;
                absMidCoordPos = vec2(0.5);
                midCoordPos = vec2(0.0);
                vec3 ipbrSavedColorP = colorP;
                colorP = texture2D(tex, texCoord).rgb;
                GenerateNormals(normalM, colorP);
                colorP = ipbrSavedColorP;
                absMidCoordPos = ipbrSavedAbsMidCoordPos;
                midCoordPos = ipbrSavedMidCoordPos;
            }
        #endif
        #ifdef COATED_TEXTURES
            #if defined GBUFFERS_ENTITIES || defined GBUFFERS_HAND
                CoatTextures(color.rgb, noiseFactor, playerPos, false);
            #else
                CoatTextures(color.rgb, noiseFactor, playerPos, doTileRandomisation);
            #endif
        #endif
    #endif

    // The tables may recolour or alpha-out the fragment (glowing ores, hiding armour).
    Albedo = color;

    // Diagnostics for the normal that reaches `normal`.
    //   x = 1 if the safety net below replaced normalM
    //   y = |normalM|^2 before the safety net
    //   z = |normalM|^2 after it
    {
        float ipbrLenBefore = dot(normalM, normalM);
        ipbrNormalDebug = vec3(0.0, ipbrLenBefore, 0.0);

        // Safety net.  A non-finite normal written into the G-buffer breaks every
        // downstream pass that touches it, so a normal that is not unit length
        // falls back to the geometric one.  `!(x > a && x < b)` deliberately
        // catches NaN too.
        //
        // This is under test: the recorded normalMap is non-zero, so normalM
        // should be assigned a valid perturbed normal, yet `normal` comes out
        // geometric.  This block is the only conditional between the two.
        if (!(ipbrLenBefore > 0.5 && ipbrLenBefore < 1.5)) {
            normalM = geoNormal;
            ipbrNormalDebug.x = 1.0;
        }
        ipbrNormalDebug.z = dot(normalM, normalM);
    }
    normal = normalM;

#endif // IPBR
