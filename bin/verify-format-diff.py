#!/usr/bin/env python3
"""Verify a prose-format sweep: flag every change that is NOT a
rewrap or a dash removal/replacement.

== Intent ==

A large formatting-only diff is unreviewable by eye. This script
reduces it to a short human-review list by proving, mechanically,
that every change belongs to one of exactly two allowed classes:

  1. rewrap: whitespace-only changes (one-sentence-per-line joins,
     splits, indentation) - invisible after whitespace stripping.
  2. dash removal: a unicode em/en-dash or an ASCII "-" / "--"
     surrogate replaced by one of , : . ( ) or deleted outright.

Any change outside those two classes is a real content change and
is flagged, one entry per contiguous diff region, with file, line,
and surrounding context. The flag list is the deliverable: it is
the complete set of edits a reviewer must actually read.

== Method ==

For each changed file, compare the HEAD blob against the working
tree on a whitespace-free character stream (see `stream()`).
Unicode dashes normalize to a token D; ASCII '-' stays '-'.
difflib then yields a small number of diff regions; inside each
region we admit only the atomic edits listed above and flag the
region if it contains anything else.

== Caveats (accepted, conservative) ==

- "--" -> "-" shortening inside a run is masked (counts as dash
  removal, which the sweep was allowed to do anyway).
- Whitespace edits inside code blocks are invisible (a rewrap is
  whitespace-only by definition, so this cannot be distinguished).
- difflib occasionally picks a misaligned pairing inside a region
  (e.g. reports "del 's'" where no 's' was truly deleted). The
  printed old/new segments and context are authoritative; the atom
  list is a hint only.

Usage: verify-format-diff.py [path]   (default: cwd)
"""

import difflib
import os
import subprocess
import sys

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

REPL = set(',:.()')   # punctuation an em-dash may be replaced by
DASH = '\x00'         # internal token for a normalized unicode dash
CTX = 45              # context chars shown around each flagged region
SEG = 90              # max chars of a changed segment shown per flag


# ------------------------------------------------------------------
# Normalization
# ------------------------------------------------------------------

def stream(text):
    """Build the comparison stream for one file version.

    Returns (chars, lines): `chars` is the file with all whitespace
    removed and unicode dashes (em-dash, en-dash, horizontal bar)
    mapped to DASH. `lines[i]` is the 1-based source line that
    produced `chars[i]`, so flags can point back at real files.

    Whitespace removal is what makes rewraps free: joining or
    splitting lines changes nothing in this stream.
    """
    out, loc = [], []
    for ln, line in enumerate(text.split('\n'), 1):
        for ch in line:
            if ch.isspace():
                continue
            out.append(DASH if ch in '—–―' else ch)
            loc.append(ln)
    return ''.join(out), loc


def in_dash_run(s, i):
    """True if s[i] borders another '-'; identifies "--" surrogates.

    A lone '-' deleted between word characters (a-b -> ab) is a real
    edit and must flag; one half of a "--" pair disappearing under a
    replacement is just the surrogate being consumed and is allowed.
    """
    return (i > 0 and s[i - 1] == '-') or (i + 1 < len(s) and s[i + 1] == '-')


def allowed_pair(o, n):
    """True if old char `o` may be replaced by new char `n`."""
    return o in (DASH, '-') and n in REPL


def allowed_del(s, i):
    """True if s[i] may be deleted outright.

    A normalized unicode dash may always vanish (em-dash removal is
    one of the allowed classes). An ASCII '-' may vanish only inside
    a multi-dash run, i.e. as half of a "--" surrogate.
    """
    c = s[i]
    return c == DASH or (c == '-' and in_dash_run(s, i))


# ------------------------------------------------------------------
# Reporting helpers
# ------------------------------------------------------------------

def ctx(s, a, b):
    """Window of `s` around region [a,b), markers >>> <<< on the change."""
    lo, hi = max(0, a - CTX), min(len(s), b + CTX)
    return s[lo:a] + '>>>' + s[a:b] + '<<<' + s[b:hi]


def seg(s, a, b):
    """The changed region itself, truncated for display."""
    t = s[a:b]
    return t if len(t) <= SEG else t[:SEG] + '...'


# ------------------------------------------------------------------
# Core check
# ------------------------------------------------------------------

def check(path, old, new):
    """Compare two file versions; return (flags, stats).

    flags: one entry per diff region containing a disallowed atom.
    stats: counts of allowed substitutions and dash removals, so the
    summary can show how much of the diff was auto-verified.
    """
    so, lo = stream(old)
    sn, ln = stream(new)
    flags = []
    stats = {'sub': 0, 'del': 0}
    sm = difflib.SequenceMatcher(None, so, sn, autojunk=False)
    for op, a1, a2, b1, b2 in sm.get_opcodes():
        if op == 'equal':
            continue
        oseg, nseg = so[a1:a2], sn[b1:b2]
        # Collect the disallowed atoms inside this region. If `bad`
        # stays empty, the whole region was a permitted format change.
        bad = []
        if op == 'replace':
            # Zip the two sides pairwise; each differing pair must be
            # a dash->punctuation substitution.
            for k, (co, cn) in enumerate(zip(oseg, nseg)):
                if co == cn:
                    continue
                if allowed_pair(co, cn):
                    stats['sub'] += 1
                else:
                    bad.append(f"{co!r}->{cn!r}")
            # Length mismatch: the tail of the longer side is a
            # delete or insert, judged by the same rules.
            for k in range(len(nseg), len(oseg)):
                i = a1 + len(nseg) + k
                if allowed_del(so, i):
                    stats['del'] += 1
                else:
                    bad.append(f"del {so[i]!r}")
            for k in range(len(oseg), len(nseg)):
                bad.append(f"ins {sn[b1 + len(oseg) + k]!r}")
        elif op == 'delete':
            # A run of deleted chars is allowed only if every char
            # is a removable dash; one bad char flags the region.
            for k in range(len(oseg)):
                i = a1 + k
                if allowed_del(so, i):
                    stats['del'] += 1
                else:
                    bad.append('delete')
                    break
        elif op == 'insert':
            # No insertion is ever a format change: new text is new
            # content by definition and always goes to the reviewer.
            bad.append('insert')
        if bad:
            # Cap the atom list; the region context below carries
            # the full truth anyway.
            if len(bad) > 12:
                bad = bad[:12] + [f'... +{len(bad) - 12} more']
            # Line number comes from the old side when possible
            # (a familiar location for the reviewer), else the new.
            line = lo[a1] if a1 < len(so) else (ln[b1] if b1 < len(sn) else 0)
            flags.append((line, ', '.join(bad),
                          ctx(so, a1, a2), ctx(sn, b1, b2),
                          seg(so, a1, a2), seg(sn, b1, b2)))
    return flags, stats


# ------------------------------------------------------------------
# Driver: enumerate changed files, print the review list
# ------------------------------------------------------------------

def main():
    # The argument names a location, not a repo root: porcelain paths
    # below are reported relative to the toplevel and the file reads
    # join them onto `repo`, so resolve the enclosing repo first.
    # Default location is the call site, i.e. the repo it sits in.
    where = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
    if not os.path.isdir(where):     # tolerate a file path argument
        where = os.path.dirname(where)
    repo = subprocess.run(['git', '-C', where, 'rev-parse', '--show-toplevel'],
                          capture_output=True, text=True,
                          check=True).stdout.strip()
    # `git status --porcelain` is read-only and covers every diff
    # class; untracked and newly-added/copied entries are skipped in
    # the loop: the check verifies checked-in files against HEAD, so
    # content with no HEAD blob is out of scope.
    out = subprocess.run(['git', '-C', repo, 'status', '--porcelain'],
                         capture_output=True, text=True, check=True).stdout
    total_flags = total_sub = total_del = 0
    for line in out.splitlines():
        if not line:
            continue
        state, path = line[:2], line[3:]
        old_name = None            # set on rename entries (old -> new)
        if ' -> ' in path:
            old_name, path = path.split(' -> ', 1)
            old_name = old_name.strip('"')
        path = path.strip('"')
        full = os.path.join(repo, path)
        if 'D' in state:
            old = subprocess.run(['git', '-C', repo, 'show', f'HEAD:{path}'],
                                 capture_output=True, text=True).stdout
            new = ''
        elif state == '??' or 'A' in state or 'C' in state:
            continue    # no HEAD blob: not a checked-in file
        elif os.path.islink(full) or not os.path.isfile(full):
            # gitlinks and typechanged symlinks carry no diffable file
            # content; name them so the review list stays complete.
            print(f'== {path} (skipped: not a regular file)')
            continue
        else:
            old = subprocess.run(['git', '-C', repo, 'show',
                                  f'HEAD:{old_name or path}'],
                                 capture_output=True, text=True,
                                 check=True).stdout
            new = open(full, encoding='utf-8', errors='replace').read()
        flags, stats = check(path, old, new)
        total_sub += stats['sub']
        total_del += stats['del']
        if flags:
            total_flags += len(flags)
            print(f'== {path} ({len(flags)} region(s) flagged)')
            for ln, what, oc, nc, os_, ns_ in flags:
                print(f'  ~L{ln}  {what}')
                print(f'    old seg: {os_!r}')
                print(f'    new seg: {ns_!r}')
                print(f'    old ctx: {oc}')
                print(f'    new ctx: {nc}')
    print()
    print(f'{total_sub} dash->punct substitutions, '
          f'{total_del} dash removals (allowed)')
    print(f'{total_flags} flagged region(s) for review')


if __name__ == '__main__':
    main()
