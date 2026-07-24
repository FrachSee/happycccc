#!/usr/bin/env python3
"""Stable per-episode character counter for the screenplay.

Counting rule (deterministic and reproducible):
- An episode starts at a line matching '## 第N集' and ends before the next such line.
- The episode heading line itself is NOT counted (it is metadata, not performed text).
- We count every character of the episode body EXCEPT whitespace
  (ASCII space, tab, newline, carriage return, and the full-width space U+3000).

Usage:
    python3 scripts/count_chars.py path/to/screenplay.md
"""
import re
import sys

WHITESPACE = {" ", "\t", "\n", "\r", "\u3000"}


def count_body(body: str) -> int:
    return sum(1 for ch in body if ch not in WHITESPACE)


def main(path: str) -> int:
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()

    # Split keeping the headings.
    parts = re.split(r"(?m)^(##\s*第[0-9一二三四五六七八九十百]+集[^\n]*)$", text)
    # parts[0] is any preamble before the first episode; then heading, body, heading, body...
    episodes = []
    for i in range(1, len(parts), 2):
        heading = parts[i].strip()
        body = parts[i + 1] if i + 1 < len(parts) else ""
        episodes.append((heading, count_body(body)))

    total = 0
    print(f"{'Episode':<40}{'chars':>8}{'  flag'}")
    print("-" * 60)
    for heading, n in episodes:
        total += n
        flag = "" if 650 <= n <= 750 else ("LOW" if n < 650 else "HIGH")
        print(f"{heading:<40}{n:>8}  {flag}")
    print("-" * 60)
    print(f"{'TOTAL episodes: ' + str(len(episodes)):<40}{total:>8}")
    if episodes:
        print(f"{'AVERAGE':<40}{total // len(episodes):>8}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python3 scripts/count_chars.py <screenplay.md>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
