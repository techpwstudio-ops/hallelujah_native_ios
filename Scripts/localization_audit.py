#!/usr/bin/env python3
"""Heuristic audit for hard-coded user-facing strings in App/**/*.swift.

Usage:
  Scripts/localization_audit.py                 # report offenders (exit 1 if any)
  Scripts/localization_audit.py --files a.swift # limit to files
  Scripts/localization_audit.py --catalog       # (re)build App/Resources/Localizable.xcstrings
                                                # from every localizable literal in the code

A literal is "localizable" when it is the argument of Text/Label/Button/
TextField/Toggle/Section/Picker/navigationTitle/accessibility*/alert/confirmationDialog
(SwiftUI treats those as LocalizedStringKey) or of String(localized:)/
LocalizedStringResource. A literal is an OFFENDER when it looks like prose
(starts with a letter, contains a space or ends with punctuation/uppercase word,
>= 3 chars) and is used anywhere else outside logs, comments, #Preview, enum raw
values, SF Symbol / asset names, URLs, endpoints, dictionary keys and formats.
Heuristic: review findings, do not trust blindly.
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "App"
LOCALIZABLE_CALL = re.compile(
    r'(?:(?:Text|Label|Button|TextField|SecureField|Toggle|Section|Picker|Menu|Link|NavigationLink|'
    r'navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|help|alert|confirmationDialog|'
    r'LocalizedStringKey|LocalizedStringResource|L10n\.tr|\.show)\s*\(\s*(?:localized:\s*)?|String\(localized:\s*|AttributedString\(appLocalized:\s*)'
    r'"((?:[^"\\]|\\.)*)"')
STRING = re.compile(r'(?<![\w#])"((?:[^"\\]|\\.)+)"')
SKIP_CONTEXT = re.compile(
    r'(logger\.|AppLogger|\.debug\(|\.info\(|\.warning\(|\.error\(|print\(|assert|fatalError|precondition|'
    r'systemName:|Image\(|UIImage\(|Color\(|\.custom\(|Notification\.Name|forKey|UserDefaults|'
    r'Endpoint\.|\.get\(|\.post\(|\.patch\(|\.delete\(|URL\(string|CodingKeys|case \w+ = |'
    r'DateFormatter|dateFormat|Locale\(identifier|@Test|#expect|#Preview|accessibilityIdentifier|'
    r'id: "|identifier|queryItems|URLQueryItem|setValue|forHTTPHeaderField|JSONSerialization|\["|NSUserActivity|'
    r'static let \w*(Key|ID|Id|Name|Path|Identifier|Scheme|Host)\w*\s*=|AppRoute|DependencyContainer)')

INT_HINT = re.compile(r'(count|Count|minutes|days|months|weeks|seconds|hours|index|total|limit|number|max|min|\bn\b|years|plays|songs|likes|items|size)', re.I)

def unescape(k: str) -> str:
    k = re.sub(r'\\u\{([0-9A-Fa-f]+)\}', lambda m: chr(int(m.group(1), 16)), k)
    return k.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')

def to_format_key(raw: str):
    """Swift string with \\(expr) interpolations -> catalog key with %@ / %lld, or None if unparseable."""
    out, i = [], 0
    while i < len(raw):
        if raw.startswith('\\(', i):
            depth, j = 1, i + 2
            while j < len(raw) and depth:
                depth += (raw[j] == '(') - (raw[j] == ')')
                j += 1
            if depth: return None
            expr = raw[i + 2:j - 1]
            out.append('%lld' if INT_HINT.search(expr) else '%@')
            i = j
        else:
            out.append(raw[i]); i += 1
    return ''.join(out)

def looks_like_prose(s: str) -> bool:
    if len(s) < 3 or '%' in s and ' ' not in s: return False
    if re.fullmatch(r'[\w./:-]+', s) and ' ' not in s: return False      # identifiers, paths, keys
    if s.startswith(('http', '/', '#', '.', '$')): return False
    if re.fullmatch(r'[\W\d_]+', s): return False
    return bool(re.search(r'[A-Za-z]{3,}', s)) and (' ' in s or s[0].isupper())

def scan(path):
    text = path.read_text(encoding='utf-8', errors='ignore')
    loc, off = set(), []
    in_block = False
    for n, line in enumerate(text.splitlines(), 1):
        code = line
        if in_block:
            if '*/' in code: in_block, code = False, code.split('*/', 1)[1]
            else: continue
        if '/*' in code and '*/' not in code: in_block, code = True, code.split('/*', 1)[0]
        code = re.sub(r'//.*$', '', code) if not re.search(r'"[^"]*//[^"]*"', code) else code
        if not code.strip(): continue
        for m in LOCALIZABLE_CALL.finditer(code):
            loc.add(m.group(1))
        covered = [m.span(1) for m in LOCALIZABLE_CALL.finditer(code)]
        if SKIP_CONTEXT.search(code): continue
        for m in STRING.finditer(code):
            if any(a <= m.start(1) < b for a, b in covered): continue
            s = m.group(1)
            if looks_like_prose(s): off.append((n, s))
    return loc, off

def main():
    args = sys.argv[1:]
    files = [pathlib.Path(a) for a in args[args.index('--files') + 1:]] if '--files' in args else sorted(APP.rglob('*.swift'))
    keys, total = set(), 0
    for f in files:
        if '--catalog' in args and f.name == 'Country.swift': continue
        loc, off = scan(f)
        keys |= loc
        if '--catalog' in args:
            keys |= {t for _, t in off}   # literals passed to LocalizedStringKey-typed params
        if off and '--catalog' not in args:
            for n, s in off:
                print(f"{f.relative_to(ROOT)}:{n}: {s}")
            total += len(off)
    if '--catalog' in args:
        cat_path = APP / 'Resources' / 'Localizable.xcstrings'
        cat = json.loads(cat_path.read_text())
        for k in sorted(keys):
            k = to_format_key(k) if k and '\\(' in k else k
            k = unescape(k) if k else k
            if k and k not in cat['strings']:
                cat['strings'][k] = {"extractionState": "manual", "localizations": {"en": {"stringUnit": {"state": "translated", "value": k}}}}
        cat_path.write_text(json.dumps(cat, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
        print(f"catalog: {len(cat['strings'])} keys")
        return 0
    print(f"{total} suspected hard-coded strings in {len(files)} files")
    return 1 if total else 0

if __name__ == '__main__':
    sys.exit(main())
