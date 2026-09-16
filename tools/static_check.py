#!/usr/bin/env python3
"""Structural checks on Tweak.xm that do not need a compiler.

This is not a substitute for compiling. It catches the mistakes that are
expensive to find on-device: an unbalanced block, a hook installed without a
matching orig pointer, and -- most importantly -- a touch probe that changes a
return value instead of only observing it.
"""
import re
import sys

src = open('Tweak.xm', encoding='utf-8').read()

# Strip comments, then string/char literals, so brace counting ignores text.
s = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
s = re.sub(r'//[^\n]*', '', s)
s = re.sub(r'@?"(?:\\.|[^"\\\n])*"', '""', s)
s = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", s)

ok = True
for name, op, cl in (("brace", "{", "}"), ("paren", "(", ")"), ("bracket", "[", "]")):
    a, b = s.count(op), s.count(cl)
    status = "OK" if a == b else "MISMATCH"
    if a != b:
        ok = False
    print(f"{name}: {a} {op} vs {b} {cl} -> {status}")

print("\n--- globals declared but referenced only once (likely unused) ---")
globs = set()
for line in src.splitlines():
    line = line.strip()
    if not line.startswith('static ') or '(' in line:
        continue
    m = re.match(r'static (?:const )?[A-Za-z_][\w\s*<>:]*?\s\*?(\w+(?:\s*,\s*\*?\w+)*)\s*(?:=.*)?;$', line)
    if not m:
        continue
    for n in m.group(1).split(','):
        n = n.strip().lstrip('*')
        if re.match(r'^[gk][A-Z]\w*$', n):
            globs.add(n)
for n in sorted(globs):
    c = len(re.findall(r'\b' + n + r'\b', src))
    if c < 2:
        print(f"  UNUSED: {n} (referenced {c}x)")
        ok = False
print(f"  checked {len(globs)} globals: {', '.join(sorted(globs))}")

print("\n--- hook / orig pointer pairing ---")
sigs = {}
for ret, name, args in re.findall(r'static ([\w\s*]+?)\(\*(Orig\w+)\)\(([^)]*)\);', src):
    sigs[name] = (ret.strip(), args.strip())
for name, (ret, args) in sorted(sigs.items()):
    hook = 'Hook' + name[4:]
    m = re.search(r'static ([\w\s*]+?)' + hook + r'\(([^)]*)\)\s*\{', src)
    if not m:
        print(f"  MISSING hook for {name}")
        ok = False
        continue
    hret = m.group(1).strip()
    if hret != ret:
        print(f"  RETURN MISMATCH {name}: orig={ret!r} hook={hret!r}")
        ok = False
    hooked = len(re.findall(r'\(IMP \*\)&' + name + r'\b', src))
    called = len(re.findall(r'\b' + name + r'\(', src))
    if hooked != 1 or called < 1:
        print(f"  WIRING {name}: installed {hooked}x, called {called}x")
        ok = False
print(f"  checked {len(sigs)} hook pairs")

print("\n--- probe hooks must return the original value unchanged ---")
for hook in ('HookHitTest', 'HookPointInside', 'HookWindowHitTest', 'HookWindowPointInside'):
    m = re.search(r'static [\w\s*]+?' + hook + r'\([^)]*\)\s*\{(.*?)\n\}', src, re.S)
    if not m:
        print(f"  MISSING {hook}")
        ok = False
        continue
    body = m.group(1)
    var = 'result' if 'HitTest' in hook else 'inside'
    returns = [r.strip() for r in re.findall(r'return\s+([^;]+);', body)]
    bad = [r for r in returns if r != var]
    # The captured value must be assigned exactly once, at the initial capture.
    writes = re.findall(r'^\s*(?:[\w\s]*\*?\s*)?\b' + var + r'\s*=(?!=)', body, re.M)
    status = "OK" if not bad and len(writes) == 1 else "PROBLEM"
    print(f"  {hook}: returns {returns}, writes to {var}={len(writes)} -> {status}")
    if bad or len(writes) != 1:
        ok = False

sys.exit(0 if ok else 1)
