# Bliss Unbound (Chocapic13' Shaders edit)

Bliss Unbound is a fork of [Bliss](https://github.com/X0nk/Bliss-Shader) by X0nk. It keeps Bliss' lighting, sky, clouds and fog, and adds these features ported from [Complementary Reimagined / Unbound](https://github.com/ComplementaryDevelopment/ComplementaryReimagined) by Complementary Development ([complementary.dev](https://www.complementary.dev/)):

- **ACT colored lighting**: voxel flood-fill block light with colored light fog. It replaces Bliss' LPV while enabled.
- **World-space reflections**: ray-traced reflections on blocks, water and glass, including your own player model. The screen-space and world-space passes can be run in either order.
- **IntegratedPBR+ materials**: per-block smoothness, reflectance, emission and subsurface values for vanilla textures, glowing ores, generated normals and coated textures.
- **Effects**: connected glass (also in shadows), portal edge glow, colored candle light, global god rays, and an always-visible End orb.

Requires Iris (tested on Iris 1.11 / Minecraft 26.2 with Sodium).

## Presets and main screen

The main settings screen has a **Profile** button with the presets `Bliss Default`, `Medium`, `High` and `Ultra`. The pack ships on **Medium**.

Three settings on the main screen are not part of any preset, so switching presets keeps them:

- **Mood**: Default (AgX), Natural (AgX Minimal), Vibrant (ACES), or Custom (the Tonemap option under Post Processing).
- **Sun Brightness**: 150k by default.
- **Moon Brightness**: 600 by default.

Presets live in [`presets/`](presets) as Iris option files (`NAME=value`). You can also drop one next to the pack as `<pack>.txt`. After editing a preset, regenerate the profiles and the shipped defaults:

```
py tools/presets.py shaders --default=Medium
```

## Installing

Download the repository as a zip (green **Code** button, then **Download ZIP**) and put it in `.minecraft/shaderpacks`.

## Following upstream Bliss

This repository is a git fork of Bliss. `main` starts at the Bliss commit it was built on, so upstream changes can be merged in:

```
git remote add upstream https://github.com/X0nk/Bliss-Shader.git
git fetch upstream
git merge upstream/Unstable
```

[`docs/PORTING.md`](docs/PORTING.md) lists every place this fork touches Bliss' own files. It also explains how to move the features onto a different Bliss version. [`docs/PORTING-NOTES.md`](docs/PORTING-NOTES.md) holds the engineering notes from the Complementary port.

## Tools

- `tools/validate.py`: compiles every program with glslangValidator for a given option set, e.g. `py tools/validate.py shaders --set=WORLD_SPACE_REFLECTIONS=true`. `world0/physics_ocean.fsh` fails in the harness only; that is a known issue.
- `tools/presets.py`: builds the Iris profiles from `presets/*.txt` and writes the default preset into the `#define`s.
- `tools/apply_options.py`: writes a saved Iris options file back into `settings.glsl`.

## Credits

- **Bliss** by [X0nk](https://github.com/X0nk/Bliss-Shader), the base of this pack.
- **Chocapic13' Shaders** by [Chocapic13](https://www.curseforge.com/minecraft/customization/chocapic13-shaders), the shader Bliss is an edit of.
- **Complementary Reimagined / Unbound** by [Complementary Development](https://www.complementary.dev/) ([GitHub](https://github.com/ComplementaryDevelopment/ComplementaryReimagined)). ACT, world-space reflections, IntegratedPBR+ and the effects listed above are ported from Complementary Unbound r5.9.1.
- Everyone listed in [`CREDITS.txt`](CREDITS.txt).

## License

- Bliss and Chocapic13's code is covered by [`LICENSE.md`](LICENSE.md).
- The Complementary-derived code (`shaders/lib/materials/**`, `shaders/lib/ipbr/**`, `shaders/lib/voxelization/**` and the hooks that call them) is redistributed as a Modified Pack under the [Complementary License Agreement 1.7](Complementary-License.txt), section 1.3.
