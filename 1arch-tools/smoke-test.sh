#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VakeWorks AB
#
# smoke-test.sh -- what a student does first, inside the image: every engine loads, a fresh group repository passes
# the check, and an uncommitted edit is refused (so the check is real). Writes the marker smoke-ok on success.
# It is 1Arch's own law E2E-FRESH (the template, rendered with its example keys and committed, passes `ias-check run`
# with exit 0 and writes check-report.json) and its canary E2E-DIRTY (an uncommitted edit of a tracked input exits 2),
# run in the Dockerfile's test stage on every architecture the image is built for. The steps are 1Arch's README,
# "How a group works with it", step 1 (keys, render, tar, git init).
# Exit 0 all held; 1 a named failure (with ias-check's page when it is the check that failed).
set -eu
B="${SMOKE_BIN:-/usr/local/bin}"                     # where the engines are (overridable only for the laws)
MARK="${SMOKE_MARK_DIR:-/usr/local/share/1arch-tools}"
fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

# S1 every engine is there and finds its shared libraries
for e in ias-check ias-template ias-multispine ias-symbols ias-cert-edges ias-code-anchors ias-assertion-graph ias-consistency; do
  [ -x "$B/$e" ] || fail "$e is not in $B"
done
for e in "$B"/ias-*; do
  if ldd "$e" 2>&1 | grep -q "not found"; then ldd "$e" >&2; fail "$(basename "$e"): a shared library is missing"; fi
done
[ -f "$ONEARCH/templates/group-project/template.json" ] || fail "\$ONEARCH ($ONEARCH) has no templates/group-project"

# S2 E2E-FRESH: the template, rendered with its example keys and committed, passes ias-check, exit 0
T="$(mktemp -d)"
"$B/ias-template" keys "$ONEARCH/templates/group-project" > "$T/keys.json"
"$B/ias-template" render "$ONEARCH/templates/group-project" "$T/keys.json" > "$T/seed.tar"
mkdir "$T/repo"
tar -xf "$T/seed.tar" -C "$T/repo"
cd "$T/repo"
git init -q -b main
git add -A
git -c user.name=smoke -c user.email=smoke@example.invalid commit -q -m seed
rc=0; "$B/ias-check" run > "$T/page.txt" 2>&1 || rc=$?
[ "$rc" = 0 ] || { cat "$T/page.txt" >&2; fail "E2E-FRESH: ias-check run exited $rc on a fresh seed (expected 0)"; }
[ -s check-report.json ] || fail "E2E-FRESH: ias-check wrote no check-report.json"

# S2b the student's Linux run (docker run --user "$(id -u):$(id -g)"): a uid with no passwd entry, HOME=/, on a
# repository it owns, exits 0 and owns the report. Switching uid needs root: the image's test stage runs as root.
if [ "$(id -u)" = 0 ] && command -v setpriv > /dev/null; then
  rm -f check-report.json
  chmod 755 "$T"
  chown -R 4242:4242 "$T/repo"
  rc=0; setpriv --reuid=4242 --regid=4242 --clear-groups env HOME=/ "$B/ias-check" run > "$T/page3.txt" 2>&1 || rc=$?
  [ "$rc" = 0 ] || { cat "$T/page3.txt" >&2; fail "NON-ROOT: ias-check run as uid 4242 exited $rc (expected 0)"; }
  [ "$(stat -c %u check-report.json)" = 4242 ] || fail "NON-ROOT: the report is not owned by the uid that ran the check"
  chown -R 0:0 "$T/repo"
else
  echo "S2b skipped: not root, so the uid cannot be switched (the image's test stage runs it as root)" >&2
fi

# S3 CANARY E2E-DIRTY: an uncommitted edit of a tracked input exits 2, so the check reads the commit
echo "% an uncommitted edit" >> paper/main.tex
rc=0; "$B/ias-check" run > "$T/page2.txt" 2>&1 || rc=$?
[ "$rc" = 2 ] || { cat "$T/page2.txt" >&2; fail "CANARY E2E-DIRTY: ias-check run exited $rc on a dirty tree (expected 2)"; }

mkdir -p "$MARK"
echo "1arch-tools smoke OK: 1Arch $(cat "$ONEARCH/ONEARCH_COMMIT" 2>/dev/null || echo unknown), $(uname -m)" \
  > "$MARK/smoke-ok"
cd /
rm -rf "$T"
echo "smoke OK"
