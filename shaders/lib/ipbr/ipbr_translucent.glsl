// ===========================================================================
//  IntegratedPBR+ -- translucent path
//
//  Included from /dimensions/all_translucent.fsh inside main(), right after the
//  texture colour is sampled.  It runs Complementary's translucent material
//  table and feeds the result into Bliss' own translucent shader.
//
//  Deliberately scoped: Complementary's material table is written against a set
//  of file-scope globals, but Bliss' translucent stage already owns names like
//  `color`, `viewPos` and `playerPos`.  Rather than rename Bliss' internals the
//  environment is declared inside a nested block, so the table sees exactly what
//  it expects and nothing leaks back out.
//
//  What is used: smoothness, highlightMult and emission, which map onto the
//  values Bliss' specular/emission path already consumes.
//  What is not: Complementary's fresnelM / reflectMult / translucentMult have
//  no consumer in Bliss (its glass and water shading is its own system), and
//  water itself is left to Bliss -- `translucentIPBR` defers to a full water
//  renderer upstream, which is not a material lookup.
// ===========================================================================

#ifdef IPBR
{
    int mat = int(irisBlockId + 0.5);

    // The translucent program does not include ipbr_globals.glsl, so alias the
    // varying here too.  Complementary declares in vec2 texCoord; keeping it a
    // plain global makes fwidth(texCoord) collapse and kills generated normals.
    #define texCoord lmtexcoord.xy

    vec4 color = ipbrBaseColor;     // texture * vertex colour, Complementary's name
    vec3 colorP = color.rgb;
    vec4 glColor = ipbrVertexColor;

    vec3 playerPos = feetPlayerPos;
    vec3 worldGeoNormal = worldSpaceNormal;
    float lViewPos = length(feetPlayerPos);
    float NdotU = dot(normal, normalize(gbufferModelView[1].xyz));

    vec2 lmCoordM = lmtexcoord.zw;

    // Weather / eye state, used by the glass distance- and rain-tweaks.
    float rainFactor = rainStrength;
    float eyeBrightnessM2 = eyeBrightnessSmooth.y > 239 ? 1.0 : 0.0;

    bool noSmoothLighting = false, noDirectionalShading = false, noGeneratedNormals = false;
    float smoothnessG = 0.0, highlightMult = 1.0, emission = 0.0;
    // reflectMult starts at 1.0 and is reduced by the table and by
    // DoTranslucentTweaks, which drives it to 0 when the camera is within about
    // two blocks.  That close-range falloff is most of what makes upstream's
    // glass look transparent instead of like a mirror.
    float fresnelM = 0.0, reflectMult = 1.0;
    bool translucentMultCalculated = false;
    vec4 translucentMult = vec4(1.0);

    // Water keeps Bliss' pipeline.  Upstream this branch hands over to a whole
    // water renderer rather than a material definition, so it only runs when
    // IPBR_WATER_MATERIAL asks for it.
    // Connected glass runs before the table (all_translucent.fsh); the table's own calls need upstream's globals.
    #ifdef CONNECTED_GLASS_EFFECT
        #define IPBR_CG_SUSPENDED
        #undef CONNECTED_GLASS_EFFECT
    #endif
    #ifdef IPBR_COMPLEMENTARY_WATER
        #include "/lib/materials/materialHandling/translucentIPBR.glsl"
    #else
        if (mat != 32000 && mat != 30020) {
            #include "/lib/materials/materialHandling/translucentIPBR.glsl"
        }
    #endif
    #ifdef IPBR_CG_SUSPENDED
        #define CONNECTED_GLASS_EFFECT
        #undef IPBR_CG_SUSPENDED
    #endif

    // Hand the parts Bliss can act on back to its specular/emission path.
    // Only realise them when the table actually classified this block, so
    // everything else keeps Bliss' resource-pack specular values.
    if (smoothnessG > 0.0) {
        ipbrTranslucentSmoothness = clamp(smoothnessG, 0.0, 1.0);
        ipbrTranslucentF0 = clamp(IPBR_SPECULAR_STRENGTH_M * 0.05 * sqrt(max(highlightMult, 0.0))
                                  * reflectMult, 0.0, 0.99);
        ipbrTranslucentEmission = IpbrToBlissEmission(emission);
        ipbrTranslucentReflectMult = reflectMult;

        // -------------------------------------------------------------------
        //  Tell Bliss this block is one of its hardcoded reflective materials.
        //
        //  all_translucent.fsh decides that with
        //      bool isReflective = abs(MATERIALS - 0.7) < 0.01 || isWater || ...;
        //  and, when set, raises f0 to harcodedF0 and marks the pixel reflective.
        //  Bliss' LabPBR path sets MATERIALS = 0.7 itself for ice and glass, but
        //  nothing in the IPBR path did, so those blocks fell through to the
        //  plain specular route carrying only the F0 computed above.  Ice lost
        //  the mirror behaviour entirely: it kept its transparency and a
        //  plausible F0, but stopped reflecting the sun and sky -- which is why
        //  the same block reflected correctly in LabPBR mode and not in IPBR.
        //
        //  Only the materials that are reflective in Bliss' own terms are
        //  marked, so everything else keeps the resource-pack specular route.
        // -------------------------------------------------------------------

        // The table edits `color` in place -- glass.gsl gives the empty part of
        // a pane a pale tint and a minimum opacity, tinted glass raises its
        // alpha, stained glass keeps the texture's.  Bliss' output blends on
        // the texture alpha, so this has to travel with it.
        ipbrTranslucentColor = color;
        ipbrTranslucentValid = true;
    }
}
#endif
