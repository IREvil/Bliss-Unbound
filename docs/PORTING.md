# Porting Bliss Unbound to another Bliss version

Almost all of the new code lives in new files. Bliss' own files only get small hooks that include and call it. To move to a newer Bliss, first try `git merge upstream/Unstable` and resolve conflicts in the hook files below. If the new version has diverged too far, copy the new files as they are and re-apply the hooks by hand, using `git diff 146d06ac1 -- <file>` as the reference. `146d06ac1` is the Bliss commit this fork starts from.

After porting, check two things. Compile with `py tools/validate.py shaders` for the default preset and for `--set=ACT_ENABLED=0`. In game, check that the Iris log says `Profile: MEDIUM`.

## New files (copy as-is)

| Path | What |
| --- | --- |
| `lib/ipbr/**` | IPBR+ glue: Complementary id decoding (`id_decode.glsl`), Complementary-named globals, and the solid/translucent material entry points (`ipbr_solid.glsl`, `ipbr_translucent.glsl`) |
| `lib/materials/**` | Complementary's material tables and methods (generated normals, coated textures, per-block materials) |
| `lib/voxelization/**` | ACT voxel volume and flood fill, the WSR voxel scene and ray march (`blissWSR.glsl`), player reflections (`playerRef.glsl`), and the SSBO declarations |
| `lib/colors/**` | Complementary light colours used by ACT |
| `presets/*.txt`, `tools/presets.py` | Presets and the generator for the `profile.*` lines |

## Hooks in Bliss files

| File | Hook |
| --- | --- |
| `block.properties`, `entity.properties`, `item.properties` | Complementary's id namespace (the ids the material tables expect); Bliss ids are recovered with `DecodeBliss*Id` |
| `shaders.properties` | ACT/WSR images and SSBOs, custom uniforms (`framemod*`), `shadowPlayer`, generated `profile.*` block, and the ACT / Debug / main screens |
| `lang/*.lang` | Names for the new options, the presets and the menus |
| `lib/settings.glsl` | All new options: ACT, WSR, IPBR, reflections quality, mood, `voxelDistance` |
| `dimensions/all_solid.fsh/.vsh` | Calls `ipbr_solid.glsl` (materials, generated normals, coated textures); albedo clamp before packing |
| `dimensions/all_translucent.fsh/.vsh` | IPBR glass/water, ACT light on translucents, deferred WSR record (`wsrTrans_img`), forward player reflection, connected glass, portal edge, tinted-glass alpha |
| `lib/specular.glsl` | IPBR reflectance and highlight model, WSR/SSR selection, water vs glass sky-only choice, deferred-WSR globals |
| `dimensions/composite1.fsh` | ACT block light, candle light, SSS fix, deferred translucent WSR resolve |
| `dimensions/composite2.fsh/.vsh`, `fogBehindTranslucent_pass.fsh`, `lib/*_fog.glsl` | Colored light fog from the ACT volume, global god rays, End orb; composite2 also clears the player-reflection bounds |
| `dimensions/composite11.fsh` | `TONEMAP_OPERATOR` (mood) |
| `dimensions/composite.fsh`, `lib/diffuse_lighting.glsl`, `all_particles.*` | Id decoding for held-item light and SSAO normals |
| `dimensions/shadowcomp.csh`, `lib/voxel_write.glsl` | ACT flood fill and id translation for the voxel write |
| `world*/shadow.vsh/.fsh`, `world0/dh_shadow.vsh` | Voxelization calls for ACT/WSR, player vertex list, player culled from the shadow map, connected-glass shadows |
| `world*/composite2.fsh`, `world0/composite3.fsh`, `world0/gbuffers_water.fsh` | Entry flags: `PLAYER_REF_TRACE`, `PLAYER_REF_CLEAR`, `WSR_TRANSLUCENT`; raised `#version` where SSBOs are used |
| `DH_*`, `lib/util.glsl`, `world1/gbuffers_weather.fsh` | Include guards (`diagonal3`, `projMAD`) so Complementary helpers can coexist |

## Host quirks that the port relies on

- In this host, `mc_midTexCoord` and Bliss' `vtexcoordam` both read as zero. Generated normals, coated textures and connected glass therefore rebuild sprite bounds from the 16px atlas grid.
- `shadow.culling = reversed` needs `const float voxelDistance`, or the voxel volumes only fill one chunk.
- Programs that use SSBOs need `#version 130` or newer. The shadow vertex shader needs `400 compatibility` for the atomics.
- Iris only recognises a boolean option that some file tests with a plain `#ifdef NAME`.
