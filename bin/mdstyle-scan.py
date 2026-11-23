#!/usr/bin/env python3
# Agent-generated
"""Detect MdStyle.md violations: wrapped sentences and em-dashes.

Read-only: reports candidate violation lines, never edits.
Skips code fences, tables, headings, HTML-comment generated fences,
and blockquote/blank separators.
"""
import re
import sys

FENCE = re.compile(r'^\s*(```|~~~)')
GENFENCE = re.compile(r'<!--\s*[A-Za-z]+:[A-Za-z0-9_-]+:(begin|end)\s*-->')
HEADING = re.compile(r'^\s*#{1,6}\s')
TABLE = re.compile(r'^\s*\|')
LISTITEM = re.compile(r'^\s*([-*+]|\d+[.)])\s')
BLOCKQUOTE = re.compile(r'^\s*>')
EMDASH = re.compile(chr(0x2014) + '|' + chr(0x2013) + '| -{2,} ')
MULTI = re.compile(r"[.!?]['\")\]]? +[`\[A-Z]")
TERM = re.compile(r'[.!?]["\'`)\]*_]*$')
ABBREV = re.compile(r'\b(e\.g|i\.e|etc|vs|cf|Fig|fig|Dr|Mr|Mrs|St|approx|resp|No|Inc|Ltd|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.$')

def scan(path):
    lines = open(path, encoding='utf-8').read().splitlines()
    in_code = in_gen = False
    in_front = bool(lines and lines[0].strip() == '---')
    front_done = not in_front
    prev_text = False  # previous line was paragraph/list text continuing a block
    prev_line = ''
    out = []
    for i, ln in enumerate(lines, 1):
        if in_front and not front_done:
            if i > 1 and ln.strip() == '---':
                front_done = True
            continue
        if GENFENCE.search(ln):
            in_gen = 'begin' in ln
            prev_text = False
            continue
        if in_gen:
            continue
        if FENCE.match(ln):
            in_code = not in_code
            prev_text = False
            continue
        if in_code:
            continue
        em = EMDASH.search(ln)
        if em:
            out.append((i, 'emdash', ln.strip()))
        for m in MULTI.finditer(ln):
            frag = ln[:m.start()].rstrip()
            word = frag.split()[-1] + '.' if frag.split() else ''
            # skip list numbers ("1. Foo"), heading numbers, single caps
            if re.match(r'^\s*(#{1,6}\s*)?[-*+]?\s*\d+$', frag):
                continue
            if not (ABBREV.search(word) or re.search(r'\b[A-Z]$', word)):
                out.append((i, 'multi', ln.strip()))
                break
        if not ln.strip() or HEADING.match(ln) or TABLE.match(ln):
            prev_text = False
            continue
        if BLOCKQUOTE.match(ln) or LISTITEM.match(ln):
            prev_line = ln
            prev_text = True
            continue
        # plain text line: a violation only if the previous line did not
        # end a sentence (a new sentence on its own line is compliant)
        if prev_text and not TERM.search(prev_line.rstrip()):
            out.append((i, 'wrap', ln.strip()))
        prev_line = ln
        prev_text = True
    return out

for p in sys.argv[1:]:
    hits = scan(p)
    if hits:
        print(f'== {p}')
        for i, kind, txt in hits:
            print(f'  {i}: [{kind}] {txt[:90]}')
