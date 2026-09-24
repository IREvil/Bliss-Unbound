"""Turn presets/*.txt into Iris profiles and make one of them the shipped default.

Each preset is an Iris options file (NAME=value per line). The script:
  1. completes every preset with the pack's current default for any option another
     preset sets, so each file is self-contained and switching profiles is exact;
  2. writes `profile.<ID>` lines between the markers in shaders.properties
     (ID = file name upper-cased, spaces -> _);
  3. writes the default preset's values into the #define lines (--default=Medium).

Options that must stay independent of presets (INDEPENDENT) are ignored.

Usage:
    py tools/presets.py <pack>/shaders [--presets=presets] [--default=Medium] [--check]
"""
import os
import re
import sys

INDEPENDENT = {"sun_illuminance", "moon_illuminance", "TONEMAP", "TONEMAP_MOOD"}
# Order the presets appear in the shader options menu. Names not listed follow, alphabetically.
PRESET_ORDER = ["Bliss Default", "Medium", "High", "Ultra"]
DEFINE_RE = r"^(?P<indent>[ \t]*)(?P<lead>(?://[ \t]*)?)#[ \t]*define[ \t]+%s\b(?P<rest>[^\n]*)$"
BEGIN = "# BEGIN generated profiles (tools/presets.py)"
END = "# END generated profiles"


def parse_options(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            if k.strip() not in INDEPENDENT:
                out[k.strip()] = v.strip()
    return out


def option_files(shaders):
    first = [os.path.join(shaders, "lib", "settings.glsl")]
    rest = []
    for root, _, files in os.walk(shaders):
        rest += [os.path.join(root, f) for f in files if f.endswith((".glsl", ".fsh", ".vsh", ".csh", ".gsh"))]
    return first + sorted(set(rest) - set(first))


def find_define(files, name):
    """(path, match) of the option's declaration: the first define carrying a [choices] list or a bare bool."""
    pat = re.compile(DEFINE_RE % re.escape(name), re.M)
    fallback = None
    for path in files:
        text = open(path, encoding="utf-8").read()
        for m in pat.finditer(text):
            rest = m.group("rest")
            if re.search(r"//\s*\[", rest) or not rest.strip() or rest.strip().startswith("//"):
                return path, m
            fallback = fallback or (path, m)
    return fallback


def current_value(m):
    rest = m.group("rest").strip()
    if not rest or rest.startswith("//"):
        return "false" if m.group("lead") else "true"
    return rest.split()[0]


def set_value(path, name, value):
    text = open(path, encoding="utf-8").read()
    m = find_define([path], name)[1]
    rest = m.group("rest")
    if value in ("true", "false"):
        lead = "" if value == "true" else "// "
        new = "%s%s#define %s%s" % (m.group("indent"), lead, name, rest)
    else:
        cm = re.search(r"(\s*//.*)$", rest)
        new = "%s#define %s %s%s" % (m.group("indent"), name, value, cm.group(1) if cm else "")
    if new == m.group(0):
        return False
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text[: m.start()] + new + text[m.end():])
    return True


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in sys.argv[1:] if a.startswith("--"))
    if not args:
        print(__doc__)
        return 2
    shaders = args[0]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    preset_dir = os.path.join(root, flags.get("presets", "presets"))
    default_name = flags.get("default", "Medium")
    check = "check" in flags

    presets = {}
    rank = {name.lower(): i for i, name in enumerate(PRESET_ORDER)}
    found = [f[:-4] for f in os.listdir(preset_dir) if f.lower().endswith(".txt")]
    found.sort(key=lambda n: (rank.get(n.lower(), len(rank)), n.lower()))
    for name in found:
        presets[name] = parse_options(os.path.join(preset_dir, name + ".txt"))
    if default_name not in presets:
        print("default preset %r not found in %s" % (default_name, preset_dir))
        return 1

    files = option_files(shaders)
    names = sorted(set().union(*presets.values()), key=str.lower)
    defaults, where = {}, {}
    for n in names:
        found = find_define(files, n)
        if not found:
            print("option %s not declared in the pack" % n)
            return 1
        where[n] = found[0]
        defaults[n] = current_value(found[1])

    # 1. complete every preset
    for p, opts in presets.items():
        full = {n: opts.get(n, defaults[n]) for n in names}
        presets[p] = full
        if not check:
            with open(os.path.join(preset_dir, p + ".txt"), "w", encoding="utf-8", newline="\n") as fh:
                fh.writelines("%s=%s\n" % (n, full[n]) for n in names)

    # 2. profile lines
    lines = [BEGIN]
    for p, full in presets.items():
        ident = re.sub(r"\W+", "_", p).upper()
        toks = [(n if v == "true" else "!" + n) if v in ("true", "false") else "%s=%s" % (n, v) for n, v in full.items()]
        lines.append("profile.%s = %s" % (ident, " ".join(toks)))
    lines.append(END)
    props_path = os.path.join(shaders, "shaders.properties")
    props = open(props_path, encoding="utf-8").read()
    block = "\n".join(lines)
    if BEGIN in props:
        props = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), lambda _: block, props, flags=re.S)
    else:
        props = block + "\n\n" + props
    if not check:
        with open(props_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(props)

    # 3. shipped defaults
    changed = []
    for n, v in presets[default_name].items():
        if defaults[n] != v:
            changed.append("%s: %s -> %s (%s)" % (n, defaults[n], v, os.path.relpath(where[n], shaders)))
            if not check:
                set_value(where[n], n, v)
    print("%d presets, %d options; default %s changes %d defines" % (len(presets), len(names), default_name, len(changed)))
    for c in changed:
        print("  " + c)
    return 0


if __name__ == "__main__":
    sys.exit(main())
