"""Iris/OptiFine-style #include resolver.

OptiFine and Iris resolve `#include "path"` as follows:
  * a path starting with '/' is relative to the shader pack's `shaders/` root
  * any other path is relative to the directory of the including file

This module inlines includes recursively and leaves every other preprocessor
directive untouched, so the result can be fed to a real GLSL compiler front end
(glslangValidator) which then evaluates #if / #ifdef itself.
"""
import os
import re

INCLUDE_RE = re.compile(r'^\s*#\s*include\s+"([^"]+)"\s*$')


class IncludeError(Exception):
    pass


def resolve_include(current_file, target, root):
    if target.startswith("/"):
        path = os.path.join(root, target.lstrip("/").replace("/", os.sep))
    else:
        path = os.path.join(os.path.dirname(current_file), target.replace("/", os.sep))
    return os.path.normpath(path)


def inline(path, root, seen=None, depth=0, _stack=None):
    """Return the fully include-expanded text of `path` (a file inside `root`)."""
    if _stack is None:
        _stack = []
    if depth > 64:
        raise IncludeError("include depth exceeded at %s" % path)
    path = os.path.normpath(path)
    if not os.path.isfile(path):
        raise IncludeError("missing include: %s" % path)
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        raise IncludeError("cannot read %s: %s" % (path, exc))

    out = []
    for lineno, line in enumerate(text.split("\n"), 1):
        m = INCLUDE_RE.match(line)
        if m:
            inc = resolve_include(path, m.group(1), root)
            rel = os.path.relpath(inc, root)
            if rel in _stack:
                raise IncludeError("circular include: %s" % " -> ".join(_stack + [rel]))
            out.append("// >>> begin include %s" % rel)
            out.append(inline(inc, root, seen, depth + 1, _stack + [rel]))
            out.append("// <<< end include %s" % rel)
        else:
            out.append(line)
    return "\n".join(out)


def preprocess_file(path, root):
    return inline(path, root)
