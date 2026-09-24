"""Apply an Iris/OptiFine saved-options file back into a pack's settings.glsl.

Iris writes `<pack>.txt` next to the shaderpack containing every option the user
changed from the shader's declared defaults.  This turns that file back into
`#define` lines, so a working configuration can become the shipped defaults.

Handling:
  * `NAME=true`   -> uncomment / add `#define NAME`
  * `NAME=false`  -> comment the define out
  * `NAME=value`  -> rewrite the value, leaving any `// [choices]` comment intact
  * `NAME=-1` / non-numeric -> written verbatim (Iris uses -1 for "auto")

Usage:
    python tools/apply_options.py <options.txt> <pack>/shaders/lib/settings.glsl [--check]
"""
import os
import re
import sys

DEFINE_RE = r"^(?P<indent>\s*)(?P<lead>(?://\s*)?)#\s*define\s+%s\b(?P<rest>[^\n]*)$"


def parse_options(path):
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def apply(path, options, check_only=False):
    text = open(path, encoding="utf-8", errors="replace").read()
    applied, missing, unchanged = [], [], []

    for name, value in sorted(options.items()):
        pat = re.compile(DEFINE_RE % re.escape(name), re.M)
        m = pat.search(text)
        if not m:
            missing.append(name)
            continue
        rest = m.group("rest")
        was_enabled = not m.group("lead")
        choice_comment = ""
        cm = re.search(r"(//\s*\[[^\]]*\].*)$", rest)
        if cm:
            choice_comment = " " + cm.group(1)

        if value.lower() in ("true", "false"):
            want_enabled = value.lower() == "true"
            new_rest = rest.strip()
            if want_enabled and was_enabled:
                unchanged.append(name)
                continue
            if not want_enabled and not was_enabled:
                unchanged.append(name)
                continue
            lead = "" if want_enabled else "// "
            replacement = "%s%s#define %s%s" % (m.group("indent"), lead, name, new_rest)
            if new_rest:
                replacement = "%s%s#define %s %s" % (m.group("indent"), lead, name, new_rest)
        else:
            current = rest.strip().split()[0] if rest.strip() else ""
            if current == value:
                unchanged.append(name)
                continue
            replacement = "%s#define %s %s%s" % (m.group("indent"), name, value, choice_comment)

        text = text[: m.start()] + replacement + text[m.end():]
        applied.append((name, value))

    if not check_only:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    print("applied   : %d" % len(applied))
    for n, v in applied:
        print("   %-38s = %s" % (n, v))
    print("already at that value: %d%s" % (len(unchanged), (" (" + ", ".join(unchanged) + ")") if unchanged else ""))
    if missing:
        print("NOT FOUND in settings.glsl: %s" % ", ".join(missing))
    return 1 if missing else 0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        print(__doc__)
        return 2
    return apply(args[1], parse_options(args[0]), "--check" in sys.argv)


if __name__ == "__main__":
    sys.exit(main())
