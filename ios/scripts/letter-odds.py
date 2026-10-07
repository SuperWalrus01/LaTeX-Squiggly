# Regenerates the table in KeyboardUI/LetterOdds.swift: python3 letter-odds.py
import glob, gzip, math, re, sys
counts = [[0.5]*26 for _ in range(27)]   # row 0: start of word, rows 1-26: a-z
words = 0
for path in glob.glob('/usr/share/man/man1/*') + glob.glob('/usr/share/man/man5/*') + glob.glob('/usr/share/man/man8/*'):
    try:
        raw = gzip.open(path).read() if path.endswith('.gz') else open(path, 'rb').read()
    except Exception:
        continue
    text = raw.decode('latin-1')
    # troff: drop request lines and inline escapes, keep the prose.
    text = '\n'.join(l for l in text.splitlines() if not l.startswith(('.', "'")))
    text = re.sub(r'\\f[A-Z]|\\\(..|\\[a-z&-]', ' ', text)
    for w in re.findall(r"[A-Za-z]+", text):
        w = w.lower()
        if len(w) > 20: continue
        words += 1
        prev = 0
        for ch in w:
            c = ord(ch) - 97
            counts[prev][c] += 1
            prev = c + 1
rows = []
for row in counts:
    total = sum(row)
    rows.append([round(math.log(v / total), 1) for v in row])
print(words, file=sys.stderr)
def p(prev, nxt): return math.exp(rows[0 if prev == ' ' else ord(prev)-96][ord(nxt)-97])
for a, b in [('q','u'),('q','i'),('t','h'),('t','g'),(' ','t'),(' ','x'),('e','r'),('e','e')]:
    print(f"P({b}|{a!r}) = {p(a,b):.4f}", file=sys.stderr)
print("    static let logP: [[Float]] = [")
for r in rows:
    print("        [" + ", ".join(f"{v}" for v in r) + "],")
print("    ]")
