================================================================================
 Perfecto Bliss -- porting notes
 Phase 1: Complementary Unbound's integratedPBR+ transplanted into Bliss
================================================================================

What this build is
------------------
Bliss is the host shader.  Everything visual, every pass, every setting that
Bliss already had is still Bliss.  On top of it this build adds Complementary
Unbound r5.9.1's **integratedPBR+** material system -- the block-by-block
material database that gives every block a sensible smoothness, F0, subsurface
scattering and emission value without needing a PBR resource pack.

A new setting on the main settings page switches between the two:

    IPBR_MODE = 0   Bliss' original LabPBR pipeline   (resource pack _n / _s)
    IPBR_MODE = 1   IntegratedPBR+                    (this port, default)

Both modes compile and ship; switching is a single dropdown.


1. The block id problem, and how it was solved
----------------------------------------------
Both packs drive their block logic from `mc_Entity.x`, which Iris fills from
`block.properties`.  The two numbering schemes are disjoint:

    Bliss          8 .. 501        (237 categories, ~15 900 block names)
    Complementary  5000 .. 32016   (403 categories, ~1 400 block names)

A blockstate can only carry ONE id, and Iris resolves duplicates first-wins
(block) / last-wins (entity, item), so a naive merge would break one pack or the
other.  Two facts made a clean solution possible:

  * only 448 block names, 28 entity names and 23 item names overlap at all
  * packing both ids into one integer is impossible -- Iris stores block ids in
    a **signed 16-bit** value on the non-Sodium path, so 32767 is the ceiling.
    (On Sodium it is a uint32, but a pack has to work on both.)
    Verified against Iris source: IrisVertexFormats / MixinBufferBuilder write
    `(short)`; the shipped docs say "-32768 .. 32767".

So the ids are kept in one namespace and translated in the shader:

    block.properties      Complementary first  -> Complementary wins (first-wins)
    entity/item.properties Complementary last  -> Complementary wins (last-wins)

    lib/ipbr/id_maps.glsl   generated Complementary id -> Bliss id lookup
    lib/ipbr/id_decode.glsl hand-written wrappers with an identity fallback

`DecodeBlissBlockId()` returns the Bliss category when one exists and the
original id otherwise, so Bliss-only modded blocks keep working and
Complementary ids with no Bliss counterpart simply match no Bliss constant.

The lookup is a generated balanced binary search tree (231 entries, ~8 integer
comparisons) evaluated in the vertex shader only; the result travels to the
fragment stage as a flat varying.

`tools/gen_ids.py` regenerates the merged libraries and the lookup from the two
original packs, so the whole thing is reproducible.


2. What was transplanted
------------------------
Verbatim, from ComplementaryUnbound_r5.9.1/shaders/:

    lib/materials/materialHandling/   terrainIPBR, entityIPBR, irisIPBR,
                                      blockEntityIPBR, translucentIPBR,
                                      deferredIPBR, *Materials
    lib/materials/materialMethods/    customEmission, generatedNormals,
                                      coatedTextures, wavingBlocks
    lib/materials/specificMaterials/  60 per-block material files

The material files are unmodified.  Everything they need from Complementary's
environment is supplied by three new files:

    lib/ipbr/ipbr_settings.glsl   turns the GUI settings into the macros the
                                  tables expect (IPBR, GLOWING_ORE_*, FANCY_GLASS,
                                  IPBR_EMISSIVE_MODE, RP_MODE, ...) and maps
                                  Bliss' WORLD/ENTITIES/HAND/BLOCKENTITIES onto
                                  Complementary's GBUFFERS_* names
    lib/ipbr/ipbr_globals.glsl    the ~40 file-scope globals and the handful of
                                  Iris uniforms the tables read
    lib/ipbr/ipbr_compat.glsl     Complementary's helper functions
                                  (CheckForColor, GetMaxColorDif, pow2, sqrt1,
                                  Bayer64, DoFoliageColorTweaks, ...)
    lib/ipbr/ipbr_solid.glsl      fills the globals in, runs the database and
                                  hands the result back to Bliss

Mapping the results onto Bliss' G-buffer (colortex8):

    .r  perceptual smoothness   <- smoothnessG
    .g  F0                      <- 0.05 * highlightMult
    .b  subsurface scattering   <- subsurfaceMode (1 -> 0.75, 2 -> 0.50, 3 -> 0.40)
    .a  emission                <- emission

Two details worth calling out:

  * Complementary's GGX uses a fixed F0 of 0.05 and scales the highlight with
    `highlightMult`, so `0.05 * highlightMult` reproduces its direct-lighting
    response inside Bliss' Fresnel model.
  * Complementary tags metals with a coloured fresnel in `materialMask` rather
    than with an F0.  Those tags are translated into LabPBR's hardcoded metal
    reflectances, which Bliss already knows how to render:
        OSIEBCA * 2  copper fresnel  -> 234/255 (copper)
        OSIEBCA * 3  gold fresnel    -> 231/255 (gold)
        OSIEBCA * 5  redstone        -> 230/255 (iron)

### Calibrating the specular response

The naive `F0 = 0.05 * highlightMult` above was wrong in practice and produced
blown-out highlights (a white smear where the sun reflected off glass).  The
reason is structural: Complementary multiplies the *output* of a highlight whose
internal Fresnel is fixed at 0.05, while Bliss feeds F0 *into* its Fresnel term
and its reflection mix.  Copying the multiplier into F0 changes the Fresnel
shape, not just the magnitude, and at normal incidence it scales the reflection
directly:

    material        highlightMult   F0 = 0.05*hM   F0 = 0.05*sqrt(hM)
    glass                 3.5           0.175            0.094
    stained glass         1.5           0.075            0.061
    iron block            2.0           0.098            0.070
    Bliss' own reflective-block F0 (glass/water, no resource pack) = 0.020

A square root keeps the material ordering while staying in a sane range, and two
more things finish the job:

  * **Intense Fresnel is a reflectance floor, not a tint.**  Complementary's
    `materialMask = 1` covers iron, quartz, obsidian, amethyst, diamond,
    emerald and deepslate, and upstream (`deferred1.glsl`) it swaps the Fresnel
    curve for `fresnelM * 0.75 + 0.25` -- a **0.25 reflectance even head-on**.
    Bliss' F0 is exactly that floor, so `IPBR_INTENSE_FRESNEL_MULT` at 100
    reproduces it.  This is what makes iron read as metal rather than as a
    slightly shiny stone.
  * **`reflectMult` is honoured.**  `DoTranslucentTweaks` drives it to 0 when the
    camera is within about two blocks of glass, which is most of why upstream's
    glass looks transparent up close instead of like a mirror.  F0 is multiplied
    by it, so close-range glass correctly falls back to pure diffuse.
  * **Copper / gold / redstone fresnels** become LabPBR's hardcoded metal
    reflectances, which Bliss already knows how to render.

Controls, none of which need a shader edit:

    IPBR_SPECULAR_STRENGTH      0..400    (100 = 1.0)  global F0 scale
    IPBR_INTENSE_FRESNEL_MULT   0..200    (100 = 1.0)  the 0.25 floor for iron,
                                                       quartz, obsidian, amethyst
    IPBR_WATER_MATERIAL         0 / 1                 Complementary's water
    IPBR_GLASS_OPACITY          0..100    (25 = 0.25)   minimum opacity of the
                                                       empty part of a glass pane

Bliss' own material settings still apply on top -- IPBR decides *what a material
is*, Bliss still decides *how it is rendered*.  `SUN_SPECULAR_MULT`,
`ROUGHNESS_TRESHOLD`, `DEFERRED_SPECULAR`, `DEFERRED_SSR_QUALITY` and
`DEFERRED_BACKGROUND_REFLECTION` all still shape the result, which is intended.

### Generated normals and coated textures

Both originate in Complementary's `materialMethods`, with host adaptations
documented in GENERATED-NORMALS-REPORT.md, and both are switched off by default:

    GENERATED_NORMALS       derives a normal map from the block texture itself
    COATED_TEXTURES         clear-coat speckle on shiny blocks

Upstream they are three lines each in the program; here the only missing piece
was the texture-space tangent basis:

  * `GENERATED_NORMALS` / `COATED_TEXTURES` define `IPBR_NEEDS_TANGENT`, which
    forces `at_tangent` on even when the resource pack ships no normal maps --
    the same thing Complementary does.
  * Bliss computes `dcdx`/`dcdy` at file scope in `all_solid.fsh`, so
    Complementary's `lib/util/miplevel.glsl` is **not** included (it would
    redeclare them); `midCoordPos`, `atlasSizeM` and `miplevel` are derived from
    Bliss' values in `ipbr_solid.glsl` instead.
  * IPBR uses a separate global `ipbrTbnMatrix`, avoiding the local `tbnMatrix`
    in `all_solid.fsh`. Its basis vectors are columns, so `GenerateNormals`
    transforms with `ipbrTbnMatrix * normalMap`, not the reverse order.
  * The terrain path calls both from `terrainMaterials.glsl`, so only the
    entity / hand / block paths call them from `ipbr_solid.glsl`.

Sliders: `GENERATED_NORMAL_MULT`, `GENERATED_NORMAL_RES`, `COATED_TEXTURE_MULT`.


3. Settings
-----------
Main settings page:   IPBR_MODE
Resource Pack Support > IntegratedPBR+:
    IPBR_EMISSIVE_MODE, MIRROR_TINTED_GLASS, HIDE_ARMOR,
    GLOWING_ORE_MASTER, GLOWING_ORE_MULT,
    GLOWING_AMETHYST, GLOWING_LICHEN, CUSTOM_EMISSION_INTENSITY,
    GENERATED_NORMALS, COATED_TEXTURES and their multipliers

Debug views for verifying the port in game (Misc Settings > DEBUG_VIEW):
    debug_MATERIAL_ID        brightness = Complementary material id
    debug_SMOOTHNESS         greyscale  = resolved smoothness
    debug_IPBR_EMISSION      greyscale  = resolved emission


4. Water, and what the translucent path does
--------------------------------------------
Water is deliberately **not** touched, and that is enforced in two places:

  * translucent water (id 32000) never enters the IPBR material table
  * Complementary's water cauldron branch in `terrainIPBR.glsl` is fenced

Complementary does not describe water as a material.  Upstream,
`specificMaterials/translucents/water.glsl` hands over to a complete water
renderer -- its own colour model, wave normals, foam, absorbance, fog and (with
world-space reflections) reflections.  Dropping that into Bliss would replace
Bliss' water, not supplement it.

The fence is a switch rather than a deletion:

    IPBR_WATER_MATERIAL 0   Bliss' water (default)
    IPBR_WATER_MATERIAL 1   Complementary's water materials, with upstream's
                            WATER_STYLE / WATERCOLOR_MODE / foam / bumpiness
                            defaults supplied (several of those macros are read
                            as `#if WATER_STYLE < 3`, where an undefined macro
                            silently evaluates to 0 -- i.e. a non-default look)

`tools/check_water_fence.py` proves the default build contains no Complementary
water code, by running the programs through glslangValidator's `-E` (so the
conditional compilation is actually performed, not just textually grepped):

    python tools/check_water_fence.py
    python tools/check_water_fence.py --set=IPBR_WATER_MATERIAL=1

Both doors are compile-time `#ifdef` guards, not runtime branches, so the dead
code is not even compiled into the default build.

Puddles are untouched too: Bliss' `Porosity` / `Puddles` feature lives on the
deferred path and was not modified.  (Complementary's puddles are a separate,
voxel-based system that needs Iris CustomImages -- out of scope for Phase 1.)

### Translucent materials

What the port does cover on the translucent path:

    tinted glass, slime, honey, stained glass + panes, glass + panes, ice,
    beacon

These come from `translucentIPBR.glsl` and are folded into the values Bliss'
translucent shader already consumes -- smoothness, F0 and emission.  The rest of
what upstream's table produces (`fresnelM`, `reflectMult`, `translucentMult`)
has no consumer in Bliss, whose glass and water shading is its own system, so it
is computed and discarded.

The table is run inside a nested scope in `all_translucent.fsh`: Bliss' stage
already owns the names `color`, `viewPos`, `playerPos` and `sunVec`, so the
environment Complementary expects is declared inside a block rather than by
renaming Bliss' internals.


5. Deliberately not ported (yet)
--------------------------------
  * Complementary's water renderer (see above -- it is a switch, off by default).
  * Complementary's nether portal effect: it needs its voxel volume, and Bliss
    has its own portal handling.
  * (Generated normals and coated textures are ported -- see section 2.)
  * Complementary's colored lighting, reflections (WSR/SSR) and its own POM.
    Bliss keeps its own; POM is active on the LabPBR path and disabled on the
    IPBR path, matching upstream (IPBR has no heightmap to trace).
  * HIDE_ARMOR > 0.  Upstream it checks Iris' `relativeEyePosition` /
    `isElytraFlying` to hide only the main player's armour; those uniforms are
    unused elsewhere in Bliss and a wrong declared type is an Iris compile
    error, so the checks are compiled out.  HIDE_ARMOR stays 0.


6. Verification
---------------
`tools/validate.py` is a compile-check harness: it resolves `#include` the way
Iris does, raises the shader to a 330/430 compatibility profile (which is what
Iris actually compiles on), injects the macros OptiFine/Iris provide, and runs
glslangValidator over every entry point.

    python tools/validate.py PerfectoBliss/shaders
    python tools/validate.py PerfectoBliss/shaders --set=IPBR_MODE=0
    python tools/validate.py PerfectoBliss/shaders --baseline=tools/baseline_bliss.txt

`--options=<pack>.txt` compiles in a saved in-game configuration.  Iris can
enable a commented-out `#define` anywhere in the tree (Bliss keeps
`DEFERRED_SPECULAR` in composite1.fsh, for instance), so the options file is
applied to the fully preprocessed source:

    python tools/validate.py PerfectoBliss/shaders --options=PerfectoBliss-r1.zip.txt

Result for this build -- 405 ok, 1 failed, 20 skipped, 426 total, and
**0 regressions** against pristine Bliss, in every configuration:

    IPBR_MODE=1 (default)      IPBR_WATER_MATERIAL=1     LPV_ENABLED=1
    IPBR_MODE=0 (LabPBR)       IPBR_EMISSIVE_MODE=3      GLOWING_ORE_MASTER=0
    GENERATED_NORMALS=1        COATED_TEXTURES=1         IPBR_SPECULAR_STRENGTH=200

The 20 skips are the Distant Horizons programs, whose symbols are injected by
DH's own shader patcher and cannot be modelled here.  The 1 failure
(`world0/physics_ocean.fsh`) is a pre-existing Bliss/harness artifact: Bliss
declares `uniform sampler2D texture` and the file calls `texture(...)` as a
function, which only clashes once the harness raises the GLSL version.

Drive-by fixes found by the harness:

  * `dimensions/all_translucent.vsh` declared `uniform int entityId` only under
    `#if defined ENTITIES` while reading it under `ENTITIES || BLOCKENTITIES`,
    so `gbuffers_block_translucent` did not compile.
  * `diagonal3` and `projMAD` are defined in both `lib/util.glsl` and the
    program bodies with different parameter names.  GLSL treats that as a hard
    error, so `gbuffers_damagedblock` did not compile once the user's options
    were loaded.  Both are now `#ifndef`-guarded.

Together these fix 10 programs that pristine Bliss fails to compile in the
configuration below.

Other tooling:
    tools/apply_options.py      turn a saved <pack>.txt back into defaults
    tools/gen_ids.py            regenerate merged .properties + id_maps.glsl
    tools/check_water_fence.py  prove no Complementary water in the default build
    tools/check_screens.py      verify every shaders.properties GUI reference
    tools/props_analyze.py      compare the two id namespaces
    tools/ipbr_deps.py          list what the IPBR closure needs from the host
    tools/include_closure.py    resolve an #include closure


7. Licensing
------------
Complementary's licence (section 1.3) permits redistribution as a Modified Pack
provided the original is credited, its licence file is shipped unmodified, the
name does not contain "Complementary", the pack looks noticeably different, and
there is a significant amount of human-written code contributing to the
visuals.  `Complementary-License.txt` is included unchanged; the credit is in
CREDITS.txt.  If this pack is ever published, keep both.

Bliss is derived from Chocapic13's shaders and carries its own terms
(LICENSE.md) -- read those before distributing either.


---

## GENERATED_NORMALS

Works. The full investigation is in `GENERATED-NORMALS-REPORT.md`; the two root
causes were, in order of discovery:

1. **Variable shadowing.** `all_solid.fsh` declares `mat3 tbnMatrix` as a local inside
   `main()`. The IPBR block is included into `main()`, so assigning `tbnMatrix` there
   wrote to Bliss' local, while `GenerateNormals` -- a file-scope function -- read the
   never-assigned global. A zero matrix makes `normalize(normalMap * m)` return NaN,
   which the normal safety net then replaced with the geometric normal on every fragment,
   so the feature rendered exactly as if disabled. The global is now named
   `ipbrTbnMatrix` so it cannot be shadowed.
2. **Tangent handedness and alignment.** The basis must follow the texture's U/V axes,
   because `normalMap.x/y` are luminance gradients measured along +X/+Y in *texture*
   space. A purely geometric basis leaves those axes arbitrary (relief comes out rotated),
   and Complementary's convention is `binormal = cross(tangent, normal)`, not
   `cross(normal, tangent)` -- the opposite sign mirrors the relief so edges darken
   instead of catching light. The basis is now reconstructed from the screen-space
   derivatives of position and texture coordinate, with Complementary's handedness.

Both `debug_GENERATED_NORMALS` (instrumentation read from inside the function) and
`debug_SPRITE_SIZE` (state of the normal safety net) remain available.

### Verified 2026-09-22: hard texture-edge pattern

The remaining mesh was a matrix-convention mismatch. The port constructs
`ipbrTbnMatrix = mat3(ipbrT, ipbrB, ipbrN)` with basis vectors as columns, but
inherited upstream's row-vector multiplication. The final conversion now uses
`normalize(ipbrTbnMatrix * normalMap)`. A flat tangent-space normal therefore maps
back to the geometric normal instead of a camera-dependent, incorrect direction.

Only texels with nonzero gradients execute that conversion, which made the old
orientation error look like a hard texture-edge grid. Unit-length debug checks
could not detect the error.

Verified in `ernest-shader` with time frozen at noon, generated normals and deferred
specular enabled, the user's saved options, and matched ordinary/grazing views.
The grid disappears at strength 50; strengths 10 and 300 now show different relief.
All tested shader sources match the local tree. The earlier shadow-bias and specular
changes were already present in the failing baseline, so they were not sufficient.
See the verified section of GENERATED-NORMALS-REPORT.md for captures and checks.

The compile harness now treats boolean `false` as `#undef`, not `#define NAME false`.
Five focused regression tests pass; the full shader compile has no new failures.

### Historical: the texture-edge pattern investigation

With generated normals on, surfaces show a hard pattern tracing the edges between light
and dark texture regions, most visible on grass. Complementary is clean with the same
feature enabled, so this is a defect here rather than expected behaviour.

The most useful fact is a three-way comparison:

| configuration | result |
|---|---|
| `IPBR_MODE = 0` (Bliss' native LabPBR) with a resource-pack normal map | clean |
| `IPBR_MODE = 1`, `GENERATED_NORMALS` off | clean |
| `IPBR_MODE = 1`, `GENERATED_NORMALS` on | mesh |

So it is specific to generated normals inside this port -- not Bliss, not the driver, not
Iris/Sodium.

Two further observations matter:

* `debug_SPRITE_SIZE` reads cyan (red 0, green 1, blue 1): the normal safety net is not
  firing and `normalM` is a valid unit vector. No NaN and no degenerate basis.
* `GENERATED_NORMAL_MULT` from 10 to 300 changes nothing at all. A 30x range applied
  before the clamp cannot leave a scaled vector quantity unchanged.

Everything `GENERATED_NORMALS` gates has been individually excluded -- the function's
output (a forced constant normal), the tangent varying's use, the `at_tangent` request,
`IPBR_NEEDS_TANGENT` as a whole, and `ENTITY_GN_AND_CT`. Also excluded: the fwidth offset
floor, implicit texture LOD, the SSAO/SSS sampling hemisphere, camera *position*, and the
whole downstream lighting stack.

Leading remaining lead: the **normal encode/decode round trip** into colortex1
(`encode(viewToWorld(normal), ...)` in all_solid.fsh, `decode(dataUnpacked0.yw)` in
composite1.fsh). That packs the normal into two channels and reconstructs the third; a
perturbation outside the designed range would come back quantised and threshold-like
rather than proportional, which fits "the same mesh at 10 and at 300". It has never been
examined -- the investigation stayed upstream of it throughout.

Full detail, the exclusion table, and the bugs found along the way are in
`GENERATED-NORMALS-REPORT.md` at the root of this pack.

**Shipped off by default**, matching upstream. The findings in this historical
section are superseded by the verified matrix-order fix above.

### Also not working, deferred

* `COATED_TEXTURES`
* `SAFER_GENERATED_NORMALS`

## Historical: the shadowing bug in detail

`GENERATED_NORMALS` is ported faithfully from Complementary and compiles cleanly, but it
has no effect: enabling it renders identically to disabling it, with no artifact of any
kind, and its debug view shows a flat geometric normal field.

This is **not** a compile problem, an enablement problem, or a missing-input problem.
An inline replication of the algorithm, executed at the same point in the same shader
with the same texture coordinates, offset, threshold, tangent basis and guard, produces a
correct structured normal field. The algorithm works where it is; the call does not.

Full evidence, everything ruled out, and a short suspect list are in
`GENERATED-NORMALS-REPORT.md` at the root of this pack. It is unresolved and needs a
second opinion.

Everything else in this port is
verified: 405 programs compile with zero regressions against a pristine-Bliss baseline,
including in the exact in-game configuration this pack was tuned against.

Do not re-tread the ground listed under "Things already ruled out" in that report.

## Reflection F0 threshold, and the properties-file audit

### Bliss gates reflections behind an F0 threshold

`lib/specular.glsl`:

```glsl
float getReflectionVisibility(float f0, float roughness){
    float dialectrics = max(f0*255.0 - 26.0,0.0)/229.0;
```

Visibility is **exactly zero** below `26/255 = 0.102`.  The port's base F0 was 0.05, so every
ordinary material reflected nothing.  The grazing floors added later (0.03, then 0.008) were
also below the gate, which is why quartering them changed almost nothing -- they were not
weak, they were inert.

The base is now 0.11, just above the threshold: a default material opens visibility at ~0.01,
giving the faint head-on sheen Complementary has on virtually every surface, present in shade
because it is not the sun's direct term.  `IPBR_GRAZING_F0` was raised to 0.13 so it actually
exceeds the base rather than being swallowed by `max()`.

Complementary's equivalent, `deferred1.glsl`:

```glsl
fresnelM = mix(pow2(fresnelM), fresnelM * 0.75 + 0.25, intenseFresnel);
```

-- intense-Fresnel materials get a 0.25 reflectance floor at every angle.  Our port maps that
to an F0 floor of 0.25, which is above Bliss' threshold and therefore already working.

### Properties files verified against upstream

`block.properties` is a strict superset of Complementary's with **values identical** on all
404 shared ids, resolving duplicates first-wins exactly as Iris does.  `entity.properties`
(35 vs 51 ids) and `item.properties` (68 vs 93) likewise: 0 missing, 0 differing.

The 33 duplicate keys in `block.properties` are **upstream's own** -- Complementary ships them
that way, and first-wins makes the second copies intentionally inert.  The `Error while parsing
the block ID map entry for "block.10104"` warning in the log is normal for this shader and is
not a defect.  An earlier attempt to "fix" it by merging the duplicates was reverted: it
activated 33 id groups upstream leaves inactive.

**Still open:** torches do not act as light sources.  Since the id maps are correct, the fault
is in `GetVoxelIDs(mat)` or `blocklightColors.glsl`, not in the properties files.

### Reflection shape: lacquer vs wet, and where it lives

Complementary marks only eight materials as Intense Fresnel -- amethyst, deepslate, diamond,
emerald, iron, raw iron, obsidian, quartz -- via `materialMask = OSIEBCA`.  What makes those
look right is not the marker but the curve shape it selects in `deferred1.glsl`:

```glsl
fresnelM = mix(pow2(fresnelM), fresnelM * 0.75 + 0.25, intenseFresnel);
```

`fresnelM * 0.75 + 0.25` is a **constant reflectance floor**, so the sheen is present at every
angle -- a lacquer.  Ordinary materials get `pow2(fresnelM)`, an angle-dependent slope, which
reads as wetness.  The port already maps the intense path to an F0 floor of 0.25 via
`IPBR_INTENSE_FRESNEL_MULT`.

**What not to do.**  Adding floors to `ipbrSmoothness` and `ipbrF0` for all materials (the
`IPBR_GRAZING_*` experiment) reproduces the wet look and breaks two other things: it raises
smoothness to 0.7 everywhere, which fights the existing sun grazing path, and it applies to
every block including grass, because `max()` has no idea what material it is on.

**What selects correctly.**  Bliss' `getReflectionVisibility(f0, roughness)` uses BOTH values,
so a raised base F0 (0.11, just clearing the 26/255 gate) lets smooth materials -- snow
(`highlightMult = 2.0`), stone, planks -- pick up a sheen while rough ones (grass) do not.
That is Complementary's behaviour and it needs no per-block list.  `IPBR_GRAZING_REFLECTIONS`
is therefore off by default; raise `IPBR_INTENSE_FRESNEL_MULT` to extend the lacquer shape
instead.

### LPV and the Complementary path are alternatives, not companions

Bliss' LPV (`LPV_ENABLED` -> `IS_LPV_ENABLED`, `lib/voxel_common.glsl` + `lib/voxel_write.glsl`
+ `imgVoxelMask`, written from shadow.vsh by `PopulateShadowVoxel`) is Bliss' own floodfill.
**It must be fully disabled whenever the Complementary path is in use.**  They are the same
idea implemented twice, and running both would mean two voxel volumes written per frame for
one visual result.

That also settles the staging: step 3 of the plan below is not additive.  Enabling
`COLORED_LIGHTING` should turn `LPV_ENABLED` off in the same breath, and the port should be
reasoned about as a replacement for the light path rather than a layer beside it.

It is likely relevant to the open torch problem too: a build with Bliss' LPV on and
Complementary's volume unwired has no working emissive-light path at all, which matches
"torches reflect ambient light but do not act as light sources".

### ACT port progress

Landed and compiling (verified with `--set=ACT_ENABLED=true`, 405 ok / 1 pre-existing
`physics_ocean` harness failure, identical to the baseline):

| piece | state |
|---|---|
| `lib/colors/blocklightColors.glsl` | ported.  Only this one file was needed -- the other five in Complementary's `lib/colors/` depend on its whole atmospheric layer (`invNoonFactor2`, `sunVisibility2`, `skyColor`, `ambientColor`, `LIGHT_*_R/G/B`) which this tree does not have. |
| `XLIGHT_R/G/B`, `ACT_FIRE_COLOR_WARMNESS`, etc. | options added |
| `lib/voxelization/act_common.glsl` | new; pulls in `lib/ipbr/ipbr_math.glsl`, which already carries `clamp01`, `min1`, `max0`, `pow2`, `GetLuminance` from the same upstream source |
| light volume write | wired into all five shadow programs: `voxel_img` + `voxel_sampler`, the voxeliser include, and `UpdateVoxelMap(int(mc_Entity.x + 0.5))` |
| floodfill | `lib/voxelization/actFloodfill.glsl`, called from the `shadowcomp` compute pass, which hosts it in place of Bliss' LPV floodfill |

Things the host must supply, all discovered by compiling:

* `cameraPositionBestFract` / `previousCameraPositionBestFract` -- upstream derives these in
  `lib/common.glsl`; Iris 1.8+ has `cameraPositionFract`, else `fract(cameraPosition)`.
* `framemod2` -- Iris provides it; this tree only declared `framemod8`.
* `SHADOW` and `VERTEX_SHADER` -- `lightVoxelization.glsl` gates its write entry point on
  both.  Defined scoped to the include and `#undef`ed immediately after, so they cannot
  change how Bliss' own code compiles.
* `voxel_sampler`, `floodfill_sampler`, `floodfill_sampler_copy` -- the voxeliser contains
  both read and write paths, and GLSL needs every referenced identifier declared even in
  functions a given program never calls.
* `gbufferProjectionInverse`, `gbufferModelViewInverse` -- used by the behind-player
  optimisation in the floodfill.

**Work-group sizing.**  Upstream hardcodes a table for 128/192/256/384/512/768/1024.
`ivec3(N/8, min(N/16, 32), N/8)` reproduces all seven exactly *and* covers the sizes
`ACT_DISTANCE` can produce in between (64, 96, 160, 320, 448), so any distance from 4 to 32
chunks works rather than only the seven upstream shipped.

### Applying the light -- done

The volume is written and floodfilled, but nothing reads it for lighting yet, so emissive
blocks still light nothing.  Upstream applies it in `lib/lighting/mainLighting.glsl` around
line 386:

```glsl
vec3 voxelPos = SceneToVoxel(playerPos);
voxelPos = voxelPos + worldGeoNormal * 0.55;
vec4 lightVolume = vec4(0.0);
if (CheckInsideVoxelVolume(voxelPos)) {
    vec3 voxelPosM = clamp01(voxelPos / vec3(voxelVolumeSize));
    lightVolume = sqrt(GetLightVolume(voxelPosM));
    specialLighting = lightVolume.rgb;
}
lightmapXM = max(lightmapXM, mix(lightmapXM, 10.0, lightVolume.a));
specialLighting *= 1.0 + 50.0 * lightVolume.a;
specialLighting = lightmapXM * 0.13 * DoLuminanceCorrection(specialLighting + blocklightCol * 0.05);
AddSpecialLightDetail(specialLighting, color.rgb, emission);
```

The port has no `specialLighting` term -- Bliss' deferred lighting computes
`FINAL_COLOR = (Indirect_lighting + Direct_lighting) * albedo` in composite1.fsh.  So this is
a graft into Bliss' lighting equation rather than a drop-in, which is why it is left as its
own step: the colours, the `sqrt`, the `* 0.13` scale and the distance fade all have to be
reconciled against Bliss' exposure and tonemapping or the volume will land at the wrong
brightness.

### Where the light is applied

`composite1.fsh`, immediately after Bliss' own block light so it joins the same term:

```glsl
Indirect_lighting += blockLightColor;
#if COLORED_LIGHTING_INTERNAL > 0
    {
        vec3 actVoxelPos = SceneToVoxel(feetPlayerPos) + FlatNormals * 0.55;
        if (CheckInsideVoxelVolume(actVoxelPos)) {
            vec4 actLight = sqrt(GetLightVolume(clamp01(actVoxelPos / vec3(voxelVolumeSize))));
            vec3 actColor = DoLuminanceCorrection(actLight.rgb + blocklightCol * 0.05);
            Indirect_lighting += actColor * lightmap.x * (COLORED_LIGHT_STRENGTH * 0.0001);
        }
    }
#endif
```

Upstream's shape is kept: offset along the surface normal so a block reads the air in front
of it rather than inside itself, `sqrt` because the floodfill accumulates squared colour,
de-luminance so the hue survives, and scale by the block lightmap.

`COLORED_LIGHT_STRENGTH` (default 1300 -> 0.13) is upstream's factor.  It is a slider
because it has to sit against **Bliss'** exposure and tonemapping rather than
Complementary's, so the first in-game look should be treated as calibration, not verdict.

### Ordering constraint worth remembering

The ACT read-side block must sit **after** `#include "/lib/projections.glsl"` in
composite1.fsh.  `lightVoxelization.glsl`'s `SceneToVoxel` reads `cameraPosition` at file
scope, and `projections.glsl` is what declares it -- placing the block with the other early
includes fails with `'cameraPosition' : undeclared identifier`.  It also has to be file scope,
not a local inside the shading block, because the voxeliser's functions reference it.

### Three things that stop the ACT options working in-game

Found by running the pack on the live Iris 1.11.6 client and reading its log, rather than
by reasoning about it.  All three are silent or near-silent failures.

**1. `// #define NAME` does not register as an option; `#define NAME <value> // [options]` does.**

Iris logs `Unable to resolve shader pack option menu element "NAME"` for anything it has no
option for, and the screen renders the entry as nothing.  `ACT_ENABLED`,
`WORLD_SPACE_PLAYER_REF` and `PUDDLE_VOXELIZATION` were written in the bare commented form --
byte-identical to `GENERATED_NORMALS`, which *does* work -- and were dropped anyway.  A
control test settled it: a fresh name declared in the same two forms resolved only in the
valued form, in the same file, in the same screen.

So the ACT toggles are declared as `#define ACT_ENABLED 0 // [0 1]` and tested with
`#if ACT_ENABLED == 1`.  Symptom to recognise: the menu button appears but its entries are
missing and the settings are deleted from the .txt on reload.

**2. `workGroups` must be a literal ivec3 constructor.**

`Failed to process ConstDirective { IVEC3 workGroups = actWorkGroups; }: value was not a
valid ivec3 constructor`.  Iris parses this as a directive, so a reference or an expression
is rejected.  The host programs now carry an explicit `#if` table over every size
`ACT_DISTANCE` can produce (64..512), using the values verified against Complementary's own
128..1024 table.

**3. The shadow program needs `#version 330 compatibility` once `writeonly uniform` appears.**

`shadow_sodium_terrain_solid: ParseCancellationException: line 4542:11 no viable alternative
at input 'writeonly uniform'` -- Iris' ANTLR patcher does not accept the qualifier under
`#version 120`, and the whole pipeline is then disabled with
`Failed to create shader rendering pipeline, disabling shaders!`.  Complementary ships no
`#version` at all and lets Iris supply a modern one.  All five shadow programs were raised
from 120 to 330 compatibility; Bliss' legacy builtins (`gl_Vertex`, `gl_ModelViewMatrix`,
`gl_MultiTexCoord0`) need the `compatibility` profile, which is why it is 330 compatibility
rather than core.

**Also:** `cameraPositionFract` is an Iris 1.8+ uniform but is not declared in every program
the voxeliser is included from -- composite2 failed on it.  `fract(cameraPosition)` is
equivalent and always available, so it is used throughout now.

### The voxel images need an explicit format qualifier

Established by in-game diagnosis, not by reading:

* `debug_ACT` with the GUI visible came back red+green, blue zero -- ACT compiled,
  the fragment was inside the volume, and the volume held no light.
* The same view with the GUI hidden reports the *raw* stored id, and came back red
  only: **nothing was being written at all**.
* `ACT_DEBUG_SKIP_GUARD=1` (bypass `UpdateVoxelMap`'s early-out) and
  `ACT_DEBUG_WRITE_MAT=1` (store `mat` rather than the mapped id) changed nothing.
* `ACT_DEBUG_FORCE=1` (enable the path regardless of `ACT_ENABLED` and of Iris'
  `IRIS_FEATURE_CUSTOM_IMAGES`) changed nothing either.

So the write could not land under any condition.  The cause is the declaration:

```glsl
writeonly uniform uimage3D voxel_img;          // no format -> Iris has nothing to allocate
layout(r32ui) uniform writeonly uimage3D voxel_img;   // fixed
```

Every working image in this tree carries a format -- Bliss' own LPV uses
`layout(rgba8) ... image3D imgLpv1` and its voxel mask `layout(r16ui) ... uimage3D
imgVoxelMask`.  The transplanted Complementary declarations omitted it.

Formats applied: `r32ui` for `voxel_img`/`voxel_sampler` (a single uint per voxel),
`rgba16f` for `floodfill_img` and its copy (vec4 light).

**Note:** a format layout is only legal on an image, not on a sampler.  Applying
`layout(r32ui)` to `voxel_sampler` fails with
`format layout qualifiers may only be applied to images`.

### THE CAUSE: custom images must be declared in shaders.properties

`imageStore` was writing into nothing.  Iris does **not** allocate a custom image
from a `uniform ... image` declaration in the shader alone -- it needs an entry in
`shaders.properties`:

    image.<name> = <sampler> <format> <internalFormat> <type> <clear> ... <w> <h> <d>

Complementary has twelve such lines (three images x four sizes, plus more); the
port had **none** for ACT's images, while Bliss' own LPV images (`imgLpv1`,
`imgVoxelMask`) were declared correctly -- which is exactly why the LPV worked and
ACT silently did not.

Added, sized N x N/2 x N per ACT_DISTANCE value, matching Complementary's layout:

    image.voxel_img = voxel_sampler red_integer r16ui unsigned_int true false 192 96 192
    image.floodfill_img = floodfill_sampler rgba rgba16f half_float false false 192 96 192
    image.floodfill_img_copy = floodfill_sampler_copy rgba rgba16f half_float false false 192 96 192

The shader's `layout(...)` qualifier must match the declaration's internal format;
`voxel_img` is `r16ui` (Complementary's choice, not `r32ui`), `floodfill_img` is
`rgba16f`.

**The condition must not use a macro defined as an expression.**  Iris evaluates`n`n`shaders.properties` #if with a simple evaluator that does not expand a macro whose body`nis an expression.  Keyed on COLORED_LIGHTING_INTERNAL -- which here is`n(ACT_DISTANCE * 16) -- no branch matched, so **no image was ever declared**, and that`nis why the volume stayed empty through every shader-side fix.  Keyed on the plain`nmacro ACT_DISTANCE it works.  Complementary keys on COLORED_LIGHTING_INTERNAL`
because there it is a plain value.`n`n**How it was found.**  Every step above the write was proven good in game, so the
remaining question was whether the write landed.  Preprocessing `shadow.vsh` with
`glslangValidator -E` and the defines set the way Iris sets them showed the call,
`imageStore` and `voxel_img` all present -- so the code was live and the failure
was at binding, not compilation.  Reading Iris' own classes then turned up
`ShaderProperties` handling a key literally named `image.`, and Complementary's
file supplied the syntax.

**Lesson:** a transplanted system that compiles, whose gate is on, and whose write
does nothing, is very likely missing host-side resource declarations.  `image.`,
`customTexture.` and their relatives live in `shaders.properties`, not in the
shader source, and their absence is silent.

## Raw Iris ids leaking past translation

The merged `.properties` files hand the shader Complementary's numbering, while Bliss'
native systems -- LPV, held lights, SSS -- are written against Bliss' own low ids.
`lib/ipbr/id_decode.glsl` exists to bridge that, but two call sites were never updated.
Same bug class, two places.

### Held lights were dead

`lib/diffuse_lighting.glsl` fetched straight from the block-data image with the raw
uniform:

```glsl
uvec2 blockData = texelFetch(texBlockData, itemId, 0).rg;   // itemId = heldItemId
```

`item.properties` is last-wins-Complementary, so a torch's held id is **44002**, not
Bliss' 1024 (`item.1024=torch` is shadowed by `item.44002=torch`).  `texBlockData` is a
2048-slot image, so the fetch is out of range, `lightRange` comes back 0, and **every**
held light silently dies -- not just torches.  `id_maps.glsl:859` already maps
`44002 -> 1024`; it was simply never called.

Fixed at the call sites in `lib/diffuse_lighting.glsl`, which now also includes
`id_decode.glsl`.  `DecodeBlissItemIdInt` returns the raw id when unmapped, so nothing
else changes behaviour.

Also fixed: `all_solid.vsh`, `all_translucent.vsh` and `all_particles.vsh` compared the
**raw** id against Bliss' threshold --

```glsl
if(heldItemId > 999 || heldItemId2 > 999) HELD_ITEM_BRIGHTNESS = 0.9;
```

-- which, with Complementary ids starting around 40000, fired for essentially anything
held rather than only for light sources.  Now decoded first.

### The player was its own light source

`lib/voxel_write.glsl` excludes the local player deliberately:

```glsl
if (blissEntity != ENTITY_ITEM_FRAME && blissEntity != ENTITY_PLAYER)
    voxelId = uint(blissItem);
```

but `entity.properties` gives the local player a **second** Complementary id:

    entity.50016=player mannequin
    entity.50017=current_player

and `id_maps.glsl` mapped only 50016.  Since entity files are last-wins, **50017 is the id
the local player actually carries**, so `DecodeBlissEntityIdInt(50017)` returned it
unchanged, the `!= ENTITY_PLAYER` test passed when it should not have, and the player's own
body was written into the volume.  Added the alias:

```glsl
if (id == 50017) return 1601;   // "current_player" -- same entity as the mannequin
```

**Both of these are the same lesson as the image declarations and the option forms: when a
system is transplanted across a numbering or declaration boundary, the host-side pieces --
decode tables, `shaders.properties` resources, option syntax -- are not optional, and their
absence is silent.**

## The leftover debug toggle that made everything look broken

`ACT_DEBUG_FORCE` originally ORed past **both** guards:

```glsl
#if (ACT_ENABLED == 1 || ACT_DEBUG_FORCE == 1) && (defined IRIS_FEATURE_CUSTOM_IMAGES || ACT_DEBUG_FORCE == 1)
```

so a single leftover `ACT_DEBUG_FORCE=1` in the options file silently enabled the whole
ACT path.  Because of the mutual exclusion added earlier, that also **stood Bliss' LPV
down** -- leaving no working light path at all.  Symptoms, all from this one value:

* torches dead
* the player self-lit
* `debug_ACT` identical with ACT on or off, and with the floodfill on or off, because
  the path was permanently on

It now only relaxes the custom-image requirement and still requires `ACT_ENABLED`:

```glsl
#if ACT_ENABLED == 1 && (defined IRIS_FEATURE_CUSTOM_IMAGES || ACT_DEBUG_FORCE == 1)
```

Verified: `ACT_ENABLED=0 ACT_DEBUG_FORCE=1` compiles identically to the default.

**Lesson for the diagnostics in general:** a debug switch that can override a feature
gate must not be able to arm that feature on its own.  These are meant to answer "is the
code live", not to become a second, hidden enable.

## Modular view of ACT, and what that implies

Established from in-game behaviour rather than from the source, and worth writing down because
it constrains where a fix can live.

**ACT and its floodfill are extra features that do not touch the default lighting path.**
Specifically:

* The floodfill/ACT path is limited to **dynamic lights**.  It does not affect outdoor
  lighting, so either backend should be able to run without disturbing anything else.
* **Handheld lights work on the default path too**, so they do not depend on the floodfill.
  That means they should not be broken while working on ACT -- and it is a reason to back off
  from the handheld-light refactor rather than keep pulling declarations across files.  That
  refactor was attempted and reverted for exactly this reason.
* **World-space reflections replace the reflection path entirely, water included.**  SSR can
  still fill in beyond the ACT chunk distance, but Bliss' water path ray-traces its sky and
  reflects sun and cloud at all times, whereas Complementary's is SSR-based.  A correct water
  path is therefore a **hybrid of both** and is explicitly deferred.

### Consequence for the port

ACT is a **light-volume backend**, not a second copy of Bliss' lighting.  Concretely:

* The shared declarations a voxel writer needs -- `mc_Entity`, `at_midBlock`, `renderStage`,
  `cameraPosition`, `renderStage`-adjacent uniforms -- belong to *either* backend, so they are
  guarded `defined IS_LPV_ENABLED || COLORED_LIGHTING_INTERNAL > 0`.
* Only genuinely LPV-specific things (`voxel_common.glsl`, `voxel_write.glsl`,
  `PopulateShadowVoxel`) stay behind `IS_LPV_ENABLED`.
* ACT-specific images, samplers and the voxeliser stay behind `COLORED_LIGHTING_INTERNAL > 0`.

Applied to all five shadow programs.  Two of them had the ACT block accidentally nested
*inside* the LPV guard, so enabling ACT compiled the write away entirely; another two were
also missing the image-store extension for the ACT branch, since theirs was LPV-gated.

Validation after the restructure: **405 ok with ACT off and 405 ok with ACT on** -- the first
time both configurations have been clean at once.
## The one test that separates the last two causes

Everything upstream of the voxel write is now proven, and a sentinel write still lands
nowhere.  That leaves exactly two possibilities, and they look identical from `debug_ACT`:

1. the write is never reached (the shadow program does not run the branch we think), or
2. the image is not bound (the write executes and goes nowhere).

They need very different fixes, so `ACT_DEBUG_BREAK_SHADOW=1` was added: it collapses
`gl_Position` in the shadow programs.  That is visible **without the volume at all**.

* **shadow map visibly breaks** -> the program runs, and the image binding is at fault
* **nothing changes** -> the program is not executing as assumed, and the voxeliser call is
  not being reached

Run it with `ACT_ENABLED=1`, then again with `ACT_ENABLED=0` as a control.
### The break-shadow probe had to be built twice

The first version of `ACT_DEBUG_BREAK_SHADOW` reported nothing, and both reasons are worth
recording because they are easy to repeat:

1. **The insertion never matched.**  In `world0` the ACT call has two comment lines above it,
   unlike the variants, so the string replacement silently did nothing.
2. **Even if it had matched, `gl_Position` is reassigned later.**  In `world0` it is set at
   ``gl_Position = BiasShadowProjection(...)`` near the end of `main`, well after the voxel
   write.  A probe placed at the write would have been overwritten on the same vertex.

It now sits at the very end of `main()`, after `gl_Position.z /= 6.0;`, and is confirmed
present in the preprocessed source rather than assumed.

**General lesson, same shape as everything else here:** verify the instrument is in the build
before reading its result.  A diagnostic that silently fails to compile in looks exactly like
a negative result.
### The break-shadow probe needed a third version

Progression, all three needed before the test meant anything:

1. placed at the voxel write -- **never inserted**, the string did not match in `world0`
2. placed correctly but still at the write -- **overwritten**, `gl_Position` is set later in `main`
3. at the end of `main`, setting `(0,0,0,1)` -- **present, but too subtle**: every vertex lands on one
   texel, which in a flat-lit scene is not obviously wrong
4. **current**: `(3,3,3,1)`, off-screen clip space, so *all* geometry is culled and **no shadow is
   cast anywhere**.  That is unmissable.

**A diagnostic that is present but produces no visible effect is indistinguishable from one that
is absent**, and here it took three attempts to get past that.  When a probe is meant to answer a
yes/no question, it has to produce a yes/no-sized effect.
### The player was a placed torch -- the two handheld paths

Placed torches work.  Held ones did not.  The reason is that the held item was taking the
**voxel** path:

```glsl
else if (blissItem > 0 && blissItem < 1200) {
    if (blissEntity != ENTITY_ITEM_FRAME && blissEntity != ENTITY_PLAYER)
        voxelId = uint(blissItem);
}
```

That writes the held item into the light volume as though it had been **placed at the player's
own position** -- a torch's worth of light centred on the body, which is why the player read as
a torch.

The exclusion is *meant* to catch this and works in pristine Bliss, where the held item's
`entityId` is the player's id.  The merged `.properties` changed that id to Complementary's
`50017`, which was not in the decode table, so `blissEntity` stopped resolving to
`ENTITY_PLAYER` and the guard silently stopped matching.  Adding the `50017 -> 1601` alias did
not help, which tells us the hand render carries `entityId == 0` rather than the player's id --
the hand is drawn without an entity.

Fixed by requiring a real entity for the item voxel path:

```glsl
else if (blissItem > 0 && blissItem < 1200 && entityId > 0) {
```

* **held** item: no entity id -> skipped, and its light comes from the handheld path
  (`GetHandLight`), which positions it in front of the player and moves with them
* **dropped** item: carries an entity id -> still voxelises and still lights the world

This is a **pre-existing** issue: the guard is byte-identical in the pristine Bliss tree.  It was
latent there because Bliss' own ids were self-consistent, and the port's id merge broke the
assumption without touching the line.
## ACT works -- the gate was the whole bug

ACT produces coloured light. Confirmed at midnight with Bliss' LPV provably stood
down, so the propagation is Complementary's floodfill: a torch lights a grass block
warm orange, a soul torch beside it lays blue-white light over the ground.

The blocker was one term in the gate. `IRIS_FEATURE_CUSTOM_IMAGES` is not defined by
this Iris build for this pack even though `iris.features.optional` declares
`CUSTOM_IMAGES`, so `#if ACT_ENABLED == 1 && (defined IRIS_FEATURE_CUSTOM_IMAGES || ...)`
compiled the entire path out while the menu still offered the option. The gate now
tests `ACT_ENABLED` alone; the images are made real by their unconditional declaration
in `shaders.properties`, not by the feature macro.

`debug_ACT` now reports the gate as a colour bitmask (red `ACT_ENABLED`, green the
feature macro, blue the platform term) so the next regression names its own cause.

Two instruments gave confident wrong answers on the way and are worth remembering:
`tools/validate.py` supplies `IRIS_FEATURE_CUSTOM_IMAGES` in `ENGINE_DEFINES`, so it
can never reproduce this class of bug; and a reachability probe left a `TIME_WAIT`
socket that the following measurement misread as the client joining a server -- never
measure a channel you just opened.

Separately: an earlier GPU abort that took the production camera offline was **not**
ACT. Both the camera and the shader container were rendering on the same Vega 64, and
the camera never pinned a GPU. See the GPU isolation note below.

## GPU isolation for the test container

Pin the Radeon RX 550 (card0/renderD128), never the Vega 64 (card1/renderD129):
the shader container is pinned to the Vega deliberately, and a GPU reset there used to
kill the production camera (`sigabrt`, dropped off the server). `WLR_DRM_DEVICES`
alone was not enough -- the headless backend ignored it -- so the RX 550 is enforced by
removing the Vega nodes from `/dev/dri` at boot.
