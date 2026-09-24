"""Compile-check harness for Minecraft shader packs.

Minecraft's OptiFine/Iris shader pipeline compiles packs on a desktop OpenGL
*compatibility* profile, which is far more permissive than a strict
`#version 120` core compile:

  * `flat` / `noperspective` and integer varyings are accepted even when the
    source declares `#version 120`
  * OptiFine/Iris inject helper functions such as `texture2DGradARB`,
    `texture2DLod` and `texelFetch2D`
  * `gl_ModelViewMatrix`, `gl_FragData`, `attribute`/`varying`, `ftransform()`
    and friends remain available

This harness emulates that environment:
  1. resolves `#include "..."` the way Iris does (leading '/' == pack root)
  2. rewrites the `#version` line to 330 compatibility and prepends a small
     prelude that supplies the OptiFine/Iris helper functions
  3. runs glslangValidator over the result

It is a *static* check: it proves a program parses and type-checks, which is
what catches the overwhelming majority of porting mistakes. It cannot prove the
shader looks right.
"""
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from preprocess import preprocess_file  # noqa: E402

GLSLANG = os.environ.get("GLSLANG_VALIDATOR", "glslangValidator")

VERSION_RE = re.compile(r"^\s*#\s*version\s+(\d+)([^\n]*)$", re.M)

# Functions OptiFine/Iris splice into every shader.
PRELUDE = """
// ---- harness prelude: OptiFine/Iris injected helpers ----
vec4 texture2DGradARB(sampler2D s, vec2 c, vec2 dx, vec2 dy) { return textureGrad(s, c, dx, dy); }
vec4 texture2DLod(sampler2D s, vec2 c, float lod) { return textureLod(s, c, lod); }
vec4 texelFetch2D(sampler2D s, ivec2 c, int lod) { return texelFetch(s, c, lod); }
vec4 texture3DGradARB(sampler3D s, vec3 c, vec3 dx, vec3 dy) { return textureGrad(s, c, dx, dy); }
vec4 texture3DLod(sampler3D s, vec3 c, float lod) { return textureLod(s, c, lod); }
vec4 texelFetch3D(sampler3D s, ivec3 c, int lod) { return texelFetch(s, c, lod); }
// ---- end harness prelude ----
"""

EXT = {"fsh": "frag", "vsh": "vert", "csh": "comp", "gsh": "geom"}

# Macros OptiFine/Iris supply that are not written in the pack itself.
ENGINE_DEFINES = [
    "MC_VERSION=12104",
    "MC_GL_VERSION=460",
    "MC_GLSL_VERSION=460",
    "MC_OS_WINDOWS",
    "IS_IRIS",
    "MC_HAND_DEPTH=0.125",
    "MC_RENDER_QUALITY=1.0",
    "MC_NORMAL_MAP",
    "MC_SPECULAR_MAP",
    "IRIS_FEATURE_CUSTOM_IMAGES",
    "IRIS_FEATURE_SSBO",
    "IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE",
    "IRIS_FEATURE_ENTITY_TRANSLUCENT",
    "IRIS_FEATURE_REVERSED_CULLING",
    "IRIS_FEATURE_COMPUTE_SHADERS",
    "IRIS_FEATURE_FADE_VARIABLE",
    # Iris' render stage constants (values match Iris' RenderStage enum)
    "MC_RENDER_STAGE_NONE=0",
    "MC_RENDER_STAGE_SKY=1",
    "MC_RENDER_STAGE_SUNSET=2",
    "MC_RENDER_STAGE_CUSTOM_SKY=3",
    "MC_RENDER_STAGE_SUN=4",
    "MC_RENDER_STAGE_MOON=5",
    "MC_RENDER_STAGE_STARS=6",
    "MC_RENDER_STAGE_VOID=7",
    "MC_RENDER_STAGE_TERRAIN_SOLID=8",
    "MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED=9",
    "MC_RENDER_STAGE_TERRAIN_CUTOUT=10",
    "MC_RENDER_STAGE_ENTITIES=11",
    "MC_RENDER_STAGE_BLOCK_ENTITIES=12",
    "MC_RENDER_STAGE_DESTROY=13",
    "MC_RENDER_STAGE_OUTLINE=14",
    "MC_RENDER_STAGE_DEBUG=15",
    "MC_RENDER_STAGE_HAND_SOLID=16",
    "MC_RENDER_STAGE_TERRAIN_TRANSLUCENT=17",
    "MC_RENDER_STAGE_TRIPWIRE=18",
    "MC_RENDER_STAGE_PARTICLES=19",
    "MC_RENDER_STAGE_CLOUDS=20",
    "MC_RENDER_STAGE_RAIN_SNOW=21",
    "MC_RENDER_STAGE_WORLD_BORDER=22",
    "MC_RENDER_STAGE_HAND_TRANSLUCENT=23",
]

# Programs whose symbols are injected by a companion mod's own shader patcher
# (Distant Horizons supplies dhMaterialId and the DH_BLOCK_* constants), which
# this harness cannot model.  They are reported as SKIP, never as failures.
SKIP_PATTERNS = ("dh_terrain", "dh_water")


# Define profiles: name -> extra defines / removals on top of ENGINE_DEFINES.
PROFILES = {
    "default": [],
    "nomap": ["-MC_NORMAL_MAP", "-MC_SPECULAR_MAP"],
}


def to_core_compat(text, stage="frag"):
    """Raise the #version to a compatibility profile glslang accepts.

    Iris compiles packs on a desktop compatibility context, where a `#version
    120` source may still use `flat`, integer varyings, gl_FragData and the
    legacy matrix built-ins.  Emulating that needs at least 330; compute stages
    need 430.
    """
    floor = 430 if stage == "comp" else 330
    m = VERSION_RE.search(text)
    if not m:
        return "// HARNESS: no #version found\n#version %d compatibility\n" % floor + PRELUDE + text
    original = int(m.group(1))
    version = max(original, floor)
    replaced = "#version %d compatibility // HARNESS: source said %d" % (version, original)
    return text[: m.start()] + replaced + "\n" + PRELUDE + text[m.end():]


def insert_after_version(src, inject):
    """Insert preprocessor lines immediately after the #version directive."""
    if not inject:
        return src
    m = VERSION_RE.search(src)
    if m is None:
        return inject + src
    cut = src.index("\n", m.start()) + 1
    return src[:cut] + inject + src[cut:]


SETTING_RE = re.compile(r"^(\s*#\s*define\s+%s\b)([^\n]*)$", re.M)


def apply_overrides(text, overrides):
    """Rewrite `#define NAME ...` lines, the way a user would in settings.glsl.

    Also matches a commented-out definition (`//#define NAME`), because that is
    how most boolean toggles ship by default in these packs.  Programs that do
    not pull in the settings header simply keep the text as-is.
    """
    for name, value in overrides.items():
        pat = re.compile(r"^(\s*)(?://\s*)?(#\s*define\s+%s\b)([^\n]*)$" % re.escape(name), re.M)
        if value == "false":
            text = pat.sub(lambda match: "%s#undef %s" % (match.group(1), name), text)
        elif value == "true":
            text = pat.sub(lambda match: "%s%s" % (match.group(1), match.group(2)), text)
        else:
            text = pat.sub(lambda match: "%s%s %s" % (match.group(1), match.group(2), value), text)
    return text


def check_file(path, root, keep_dir=None, extra_defines=(), overrides=None):
    """Compile one shader entry point. Returns (ok, output, preprocessed_path)."""
    try:
        src = preprocess_file(path, root)
    except Exception as exc:  # noqa: BLE001
        return False, "PREPROCESS ERROR: %s" % exc, None

    ext = os.path.splitext(path)[1].lstrip(".").lower()
    stage = EXT.get(ext)
    if stage is None:
        return True, "SKIP (not a shader stage: %s)" % ext, None

    if overrides:
        src = apply_overrides(src, overrides)

    src = to_core_compat(src, stage)
    defines = list(ENGINE_DEFINES) + list(extra_defines)
    inject = "".join("#define %s\n" % d.replace("=", " ", 1) for d in defines if not d.startswith("-"))
    for d in defines:
        if d.startswith("-"):
            inject += "#undef %s\n" % d[1:]
    src = insert_after_version(src, inject)

    out_dir = keep_dir or tempfile.mkdtemp(prefix="glslchk_")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, os.path.basename(path) + "." + stage)
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(src)

    proc = subprocess.run(
        [GLSLANG, "-S", stage, "--stdin" if False else out_path],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    output = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode == 0, output, out_path


def iter_programs(root):
    """Yield every entry-point shader in a pack (the ones under world*/)."""
    for world in sorted(os.listdir(root)):
        wdir = os.path.join(root, world)
        if not os.path.isdir(wdir):
            continue
        # Only dimension folders hold entry points; `dimensions/` is a library.
        if not world.startswith("world"):
            continue
        for name in sorted(os.listdir(wdir)):
            ext = os.path.splitext(name)[1].lstrip(".").lower()
            if ext in EXT:
                yield os.path.join(wdir, name)


def parse_option_file(path):
    """Read an Iris `<pack>.txt` saved-options file into an override dict."""
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    baseline = None
    overrides = {}
    for a in sys.argv[1:]:
        if a.startswith("--baseline="):
            baseline = a.split("=", 1)[1]
        elif a.startswith("--options="):
            # Compile in the exact configuration the user is running.  Iris can
            # enable a commented-out define anywhere in the tree, not just in
            # settings.glsl, so this is applied to the fully preprocessed source.
            overrides.update(parse_option_file(a.split("=", 1)[1]))
        elif a.startswith("--set="):
            for item in a.split("=", 1)[1].split(","):
                k, _, v = item.partition("=")
                overrides[k.strip()] = v.strip()

    root = os.path.abspath(args[0]) if args else "."
    only = args[1] if len(args) > 1 else None
    verbose = os.environ.get("V") == "1"

    programs = [p for p in iter_programs(root) if only is None or only in p]
    ok_count = fail_count = skip_count = 0
    failures = []
    for prog in programs:
        rel = os.path.relpath(prog, root)
        if any(s in rel for s in SKIP_PATTERNS):
            skip_count += 1
            if verbose:
                print("SKIP %s (module-supplied symbols)" % rel)
            continue
        ok, output, out_path = check_file(prog, root, overrides=overrides)
        if ok:
            ok_count += 1
            if verbose:
                print("OK   %s" % rel)
        else:
            fail_count += 1
            failures.append((rel, output, out_path))
            print("FAIL %s" % rel)

    label = "".join(" %s=%s" % kv for kv in sorted(overrides.items()))
    print("\n[%s ] %d ok, %d failed, %d skipped, %d total"
          % (label.strip() or "default", ok_count, fail_count, skip_count, len(programs)))

    if baseline:
        base = set(l.strip() for l in open(baseline, encoding="utf-8") if l.strip())
        new = sorted(r for r, _o, _p in failures if r not in base)
        fixed = sorted(b for b in base if b not in {r for r, _o, _p in failures})
        print("\nvs baseline %s:" % baseline)
        print("  new failures : %s" % (new or "none"))
        print("  newly passing: %s" % (fixed or "none"))
        if new:
            print("  *** REGRESSION ***")

    for rel, output, out_path in failures[:12]:
        print("\n" + "=" * 70)
        print("### %s   (preprocessed: %s)" % (rel, out_path))
        print("=" * 70)
        lines = [l for l in output.split("\n") if l.strip()]
        for l in lines[:25]:
            print("   " + l)
    return 1 if fail_count else 0


if __name__ == "__main__":
    sys.exit(main())
