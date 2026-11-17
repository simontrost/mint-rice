#!/usr/bin/env python3
"""Read-only, privacy-preserving pre-commit audit for a mint-rice repo.

Reports only file paths, line numbers and category names, never matching values.
Does not modify files or Git state.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {'.git', '__pycache__', '.cache', 'node_modules', '.venv'}
SKIP_SUFFIXES = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg', '.pf2', '.woff', '.woff2',
                 '.ttf', '.otf', '.ico', '.zip', '.gz', '.xz', '.pdf', '.sqlite', '.db', '.mp4'}
TEXT_LIMIT = 5 * 1024 * 1024
RE_EMAIL = re.compile(r'(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b')
RE_HOME = re.compile(r'(?<![\w/])/home/[^/\s\x00\'"<>`]+(?:/[^\s\x00\'"<>`]*)?')
# Require a real host for webcal://; a literal regex pattern in export.sh
# must not count as a private calendar URL. Also detect Outlook published ICS URLs.
RE_PRIVATE_URL = re.compile(r'''(?ix)
    (?:
        \bwebcal://[a-z0-9][a-z0-9.-]*\.[a-z]{2,}[^\s\'"<>]*
      | \bhttps?://[^\s\'"<>]*[?&](?:token|key|secret|sig|signature|auth|code|access_token|password)=[^\s\'"<>]+
      | \bhttps?://(?:outlook\.office(?:365)?\.com|outlook\.live\.com)/owa/calendar/[^\s\'"<>]+
    )
''')
RE_POTENTIAL_SECRET = re.compile(r'''(?ix)
    (?:^|[\s\{\[\',"])\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|passwd|secret)\b
    \s*(?::|=)\s*[\'"]?([A-Za-z0-9_\-./+=:%@]{8,})
''')
RE_PEM = re.compile(r'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----')
RE_SSH = re.compile(r'\bssh-(?:rsa|ed25519|ecdsa-sha2-[a-z0-9-]+)\s+[A-Za-z0-9+/=]{100,}')
RE_URL = re.compile(r'(?i)\b(?:https?://|webcal://)')
RE_USER_PLACEHOLDER = re.compile(r'(?i)(?:/home/simon\b|/usr/share/wallpapers/personal\b)')


def audit(root: Path) -> int:
    if not (root / '.git').exists():
        print('ERROR: Not a Git repository:', root, file=sys.stderr)
        return 2
    findings: dict[str, list[str]] = {}
    file_count = 0
    all_size = 0

    def report(kind: str, rel: str, line: int | None = None) -> None:
        finding = f'{rel}:{line}' if line is not None else rel
        findings.setdefault(kind, []).append(finding)

    for dirpath, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            path = Path(dirpath) / name
            rel = str(path.relative_to(root))
            # The auditor contains literal detection examples (avoid self-matches).
            if rel == "scripts/audit.py":
                continue
            if path.is_symlink():
                dest = path.resolve()
                if not dest.is_relative_to(root):
                    report('SYMLINK OUTSIDE REPO', rel)
                continue
            try:
                size = path.stat().st_size
            except OSError:
                continue
            file_count += 1
            all_size += size
            if size > 10 * 1024 * 1024:
                report('LARGE FILE >10 MiB', rel)
            if name.lower() in {'.env', 'id_rsa', 'id_ed25519', 'credentials.json', 'secrets.json'} or name.lower().endswith(('.key', '.pem', '.p12', '.pfx', '.ics')):
                report('SENSITIVE FILENAME', rel)
            if path.suffix.lower() in SKIP_SUFFIXES or size > TEXT_LIMIT:
                continue
            try:
                raw = path.read_bytes()
                if b'\x00' in raw[:2048]:
                    continue
                content = raw.decode('utf-8')
            except (OSError, UnicodeDecodeError):
                continue
            for i, line in enumerate(content.splitlines(), 1):
                if RE_PEM.search(line):
                    report('PRIVATE KEY HEADER (critical)', rel, i)
                if RE_SSH.search(line):
                    report('SSH KEY MATERIAL (review)', rel, i)
                if RE_PRIVATE_URL.search(line):
                    report('PRIVATE / TOKENIZED URL (critical)', rel, i)
                if RE_POTENTIAL_SECRET.search(line):
                    report('POTENTIAL CREDENTIAL (review)', rel, i)
                if RE_EMAIL.search(line):
                    report('EMAIL ADDRESS (review)', rel, i)
                if RE_HOME.search(line) or RE_USER_PLACEHOLDER.search(line):
                    report('ABSOLUTE USER/MACHINE PATH (portability)', rel, i)
                if RE_URL.search(line) and path.suffix.lower() in {'.json', '.ini', '.conf', '.desktop'}:
                    report('URL IN CONFIG (review)', rel, i)

    print(f'Files scanned: {file_count} | Total size: {all_size / 1024 / 1024:.1f} MiB')
    if not findings:
        print('No automatic findings. Manual inspection and license review are still required.')
        return 0
    priorities = [
        'PRIVATE KEY HEADER (critical)', 'PRIVATE / TOKENIZED URL (critical)',
        'SENSITIVE FILENAME', 'POTENTIAL CREDENTIAL (review)', 'SSH KEY MATERIAL (review)',
        'EMAIL ADDRESS (review)', 'URL IN CONFIG (review)',
        'ABSOLUTE USER/MACHINE PATH (portability)',
        'SYMLINK OUTSIDE REPO', 'LARGE FILE >10 MiB',
    ]
    for kind in priorities:
        entries = findings.get(kind, [])
        if not entries:
            continue
        print(f'\n[{kind}] {len(entries)} finding(s)')
        for entry in entries[:30]:
            print('  ' + entry)
        if len(entries) > 30:
            print(f'  ... {len(entries)-30} more')
    print('\nResults are heuristic. No matching content or credentials are printed.')
    print('Review findings locally; do not publish until sensitive entries are removed.')
    return 1 if any('critical' in x for x in findings) else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=ROOT, help='Path to mint-rice Git repository')
    args = parser.parse_args()
    sys.exit(audit(args.repo.expanduser().resolve()))
