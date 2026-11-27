#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VakeWorks AB
#
# smoke-test-build.sh -- the 1arch-tools:<release>-build image's test: `ias-check run --build` end to end inside the image, on every
# architecture it is built for, with no network (the Dockerfile runs it RUN --network=none).
# It runs as root and makes the student's runs as uid 4242 through setpriv, as `docker run --user 4242:4242 -e
# HOME=/tmp` makes them. Facts it relies on (1Arch, the release under test): app/CheckMain.hs l.473-485 (the paper-pdf line) and
# l.502-589 (the lean step, its probe and its report fields); src/Ias/Check.hs l.404-417 (a lean edge's verdict) and
# leanPin; the template's lean/ledger.json (one row, Paper.Example, status partial) and spines.json (both spines
# planned, required empty). Needs jq (the test stage installs it; the image does not carry it).
# Exit 0 all held, and the marker test-passed is written; 1 a named failure (with ias-check's page when it is the
# check that failed).
set -eu
MARK="${TEST_MARK_DIR:-/usr/local/share/1arch-tools-build}"
FIX="${TEST_FIXTURES:-/usr/local/share/1arch-tools-build/fixtures}"
EP=/usr/local/bin/1arch-entrypoint
U=4242
# the ONE source the kpsewhich list is derived from: 1Arch's templates/group-project/paper/preamble.tex,
# plus what ias-symbol-macros.sty l.18-27 loads; a preamble change fails B2 until the list is re-derived
PREAMBLE_SHA256=476ccc72b201b56b7375370b4ebba61f43487893a6d42ca7bf0c3ed48c19f9cc
# the course's two Leans (Ias.Check leanPins): v4.36.0, the template's pin and elan's default, and v4.32.0, kept for the
# groups seeded on it
LEAN_TCS="/opt/elan/toolchains/leanprover--lean4---v4.36.0 /opt/elan/toolchains/leanprover--lean4---v4.32.0"
LATEXMK_LINE='["latexmk","-norc","-lualatex","-bibtex","-interaction=nonstopmode","-halt-on-error","-file-line-error","-no-shell-escape","main.tex"]'
fail() { echo "TEST FAIL: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail "run as root (the test switches to uid $U with setpriv)"
for c in jq setpriv ias-check ias-template git "$EP"; do command -v "$c" > /dev/null || fail "$c is missing"; done
# the tools image is the release this image is tagged with (the Dockerfile's test stage gives ONEARCH_REF)
if [ -n "${ONEARCH_REF:-}" ]; then
  [ "$(cat "$ONEARCH/ONEARCH_COMMIT")" = "$ONEARCH_REF" ] \
    || fail "the tools image was built from 1Arch $(cat "$ONEARCH/ONEARCH_COMMIT"), not ONEARCH_REF $ONEARCH_REF"
fi
as_student() { setpriv --reuid=$U --regid=$U --clear-groups env HOME=/tmp "$@"; }
gcommit() { as_student git -c user.name=test -c user.email=test@example.invalid commit -q "$@"; }
T="$(mktemp -d)"
chmod 755 "$T"
touch "$T/stamp"

# check_run LABEL WANT ARGS...: ias-check run ARGS as uid 4242 in the current repository; the exit must be WANT
check_run() {
  lbl="$1"; want="$2"; shift 2
  rc=0; as_student ias-check run "$@" > "$T/page.txt" 2>&1 || rc=$?
  [ "$rc" = "$want" ] || {
    cat "$T/page.txt" >&2
    # the join's defects name a failed checker and why (the page shows only "join defects")
    if [ -f check-report.json ]; then
      jq -c '[.steps[] | select(.step=="join")][0].detail.defects' check-report.json >&2 || true
    fi
    fail "$lbl: ias-check run $* exited $rc (expected $want)"; }
}
# jcheck LABEL EXPR: the jq expression EXPR is true on check-report.json
jcheck() {
  jq -e "$2" check-report.json > /dev/null || { cat "$T/page.txt" >&2; fail "$1: the report fails: $2"; }
}
LEAN='[.steps[] | select(.step=="lean")][0]'
ROW() { printf '[.seal[] | select(.row=="%s")][0].seal' "$1"; }

# B0 the 1arch-tools image's own test still holds here: every engine, E2E-FRESH (phase A), uid 4242, the plain alias,
#    E2E-DIRTY
SMOKE_MARK_DIR="$T/tools-mark" sh /usr/local/share/1arch-tools/smoke-test.sh > "$T/b0.txt" 2>&1 \
  || { cat "$T/b0.txt" >&2; fail "B0: 1arch-tools' smoke test fails in this image"; }

# B1 THE TOOLCHAINS: Lean 4.36.0 through elan's default and Lean 4.32.0 by its toolchain name, offline, for uid 4242
#    with HOME=/tmp; nothing under /opt/elan or /opt/texlive is world-writable; uid 4242 cannot write what ias-check's
#    probe looks at (each prefix, bin/lean, lib/lean)
# the engines read text in the locale's encoding and ias-check passes them LANG: the image's LANG must be UTF-8, or
# ias-cert-edges cannot read a Lean file with a non-ASCII character (the template's alpha), run 44844658352
[ "${LANG:-}" = C.UTF-8 ] || fail "B1: LANG is '${LANG:-}' (expected C.UTF-8: the engines decode text by the locale)"
v="$(cd / && as_student lean --version 2>&1)" || fail "B1: lean --version fails for uid $U: $v"
case "$v" in *"version 4.36.0"*) ;; *) fail "B1: lean --version says '$v' (expected version 4.36.0, elan's default)" ;; esac
v="$(cd / && as_student lean +leanprover/lean4:v4.32.0 --version 2>&1)" || fail "B1: Lean 4.32.0 fails for uid $U: $v"
case "$v" in *"version 4.32.0"*) ;; *) fail "B1: lean +leanprover/lean4:v4.32.0 says '$v' (expected version 4.32.0)" ;; esac
ww="$(find /opt/elan /opt/texlive ! -type l -perm -0002 | head -n 5)"
[ -z "$ww" ] || fail "B1: world-writable under the toolchains: $ww"
for tc in $LEAN_TCS; do
  for p in "$tc" "$tc/bin/lean" "$tc/lib/lean"; do
    if as_student test -w "$p"; then fail "B1: uid $U can write $p"; fi
  done
done

# THE SEED: the template rendered with its example keys and committed (1Arch's README, step 1), owned by uid 4242
R="$T/repo"
ias-template keys "$ONEARCH/templates/group-project" > "$T/keys.json"
ias-template render "$ONEARCH/templates/group-project" "$T/keys.json" > "$T/seed.tar"
mkdir "$R"
tar -xf "$T/seed.tar" -C "$R"
chown -R $U:$U "$R"
cd "$R"
as_student git init -q -b main
as_student git add -A
gcommit -m seed

# B2 THE TEX LIST: the preamble is the one the list was derived from, and every file resolves for uid 4242
echo "$PREAMBLE_SHA256  paper/preamble.tex" | sha256sum -c - > /dev/null \
  || fail "B2: paper/preamble.tex is not the preamble the kpsewhich list was derived from: re-derive the list"
for f in article.cls amsmath.sty amssymb.sty amsthm.sty mathtools.sty geometry.sty microtype.sty parskip.sty \
         booktabs.sty array.sty longtable.sty graphicx.sty tikz.sty hyperref.sty cleveref.sty cite.sty mathrsfs.sty \
         isomath.sty alpha.bst lmroman10-regular.otf; do
  as_student kpsewhich "$f" > /dev/null || fail "B2: kpsewhich cannot find $f"
done
for b in lualatex latexmk bibtex kpsewhich luaotfload-tool; do
  command -v "$b" > /dev/null || fail "B2: $b is not on PATH"
done

# B3 E2E-BUILD: the fresh seed, --build --require-complete, as uid 4242: exit 0, every step clean, complete; the
#    paper-pdf step ran EXACTLY the line T1 runs below
check_run E2E-BUILD 0 --build --require-complete --onearch "$ONEARCH"
jcheck E2E-BUILD '.summary.complete == true and .require_complete == true'
jcheck E2E-BUILD 'all(.steps[]; .status == "clean")'
jcheck E2E-BUILD "[.steps[] | select(.step==\"paper-pdf\")][0].argv == [$LATEXMK_LINE]"
[ -s paper/main.pdf ] || fail "E2E-BUILD: no paper/main.pdf"

# T1 THE OWN-PAPER FIXTURE: a paper a group writes on the seed's files, built with ias-check's own
#    latexmk line (-norc: the check never reads a latexmkrc), as uid 4242, HOME=/tmp, no network
O="$T/own/paper"
mkdir -p "$O"
cp "$FIX/own-paper/main.tex" "$FIX/own-paper/refs.bib" "$O/"
cp "$R/paper/preamble.tex" "$R/paper/ias-symbol-macros.sty" "$O/"
chown -R $U:$U "$T/own"
(cd "$O" && as_student env SOURCE_DATE_EPOCH=1763600000 FORCE_SOURCE_DATE=1 latexmk -norc -lualatex -bibtex \
   -interaction=nonstopmode -halt-on-error -file-line-error -no-shell-escape main.tex) > "$T/t1.txt" 2>&1 \
  || { tail -n 40 "$T/t1.txt" >&2; fail "T1: the own-paper fixture does not build with ias-check's latexmk line"; }
[ -s "$O/main.pdf" ] || fail "T1: no main.pdf"

# B4 E2E-BUILD-ACTIVE: the lean spine active and Lem requiring lean (check-e2e-test's `activate`, its lean half): the
#    partial row's theorem is sealed, so Lem-Example's lean edge is covered and FULL; the lean step's report fields
cd "$R"
as_student sh -c 'jq ".spines |= map(if .spine == \"lean\" then .status = \"active\" else . end) | .required.Lem = [\"lean\"]" spines/spines.json > spines/spines.json.new && mv spines/spines.json.new spines/spines.json'
gcommit -am "lean active"
ACTIVE="$(git rev-parse HEAD)"
check_run E2E-BUILD-ACTIVE 0 --build --require-complete --onearch "$ONEARCH"
jcheck E2E-BUILD-ACTIVE "$LEAN | .status == \"clean\" and .detail.toolchain_writable == false and .detail.seal_version_ok == true and .detail.lake_files_rewritten == []"
jcheck E2E-BUILD-ACTIVE "$(ROW Paper.Example) == \"sealed\""
jcheck E2E-BUILD-ACTIVE '[.statements[] | select(.stmt | endswith(":Lem-Example"))][0] | .verdicts.lean == "covered" and .full == true'

# B4b E2E-BUILD-V432: a group seeded on 1Arch v2026.11.21 keeps Lean v4.32.0 (the second of Ias.Check's leanPins):
#    the same repository with that release's lean/lean-toolchain and lean/lake-manifest.json (ias-core 81f0ccc^, byte
#    for byte) builds and seals with the image's Lean 4.32.0, offline: exit 0, the lean step clean, the seal's version
#    is the group's own pin, Lake rewrites nothing, the row sealed. lean/.lake is cleared on both sides of the case.
as_student rm -rf lean/.lake
as_student sh -c 'printf "leanprover/lean4:v4.32.0\n" > lean/lean-toolchain'
as_student sh -c 'printf "{\"version\": \"1.2.0\",\n \"packagesDir\": \".lake/packages\",\n \"packages\": [],\n \"name\": \"Paper\",\n \"lakeDir\": \".lake\",\n \"fixedToolchain\": false}\n" > lean/lake-manifest.json'
gcommit -am "a group on v4.32.0"
check_run E2E-BUILD-V432 0 --build --require-complete --onearch "$ONEARCH"
jcheck E2E-BUILD-V432 "$LEAN | .status == \"clean\" and .detail.seal_version_ok == true and .detail.lake_files_rewritten == []"
jcheck E2E-BUILD-V432 "$(ROW Paper.Example) == \"sealed\""
as_student git reset -q --hard "$ACTIVE"
as_student rm -rf lean/.lake

# the template's lemma with its proof replaced by sorry (ASCII; the same name and statement)
write_sorry() {
  as_student sh -c 'cat > lean/Paper/Example.lean' <<'EOF'
/-
SPDX-License-Identifier: Apache-2.0
CANARY (the image test): the template's lemma with its proof replaced by sorry.
-/
namespace Paper

def total {A : Type} (f : A -> Nat) (items : List A) : Nat := (items.map f).sum

theorem total_append {A : Type} (f : A -> Nat) : forall a b : List A, total f (a ++ b) = total f a + total f b := by
  sorry

end Paper
EOF
}

# B5 CANARY E2E-SORRY: sorry under a row claiming machine-checked: the seal fails it (sorryAx), a lean defect, exit 1
write_sorry
as_student sh -c 'jq ".nodes |= map(if .id == \"Paper.Example\" then .cert.status = \"machine-checked\" else . end)" lean/ledger.json > lean/ledger.json.new && mv lean/ledger.json.new lean/ledger.json'
gcommit -am "canary: sorry, claimed"
check_run E2E-SORRY 1 --build --require-complete --onearch "$ONEARCH"
jcheck E2E-SORRY "$LEAN | .status == \"defects\" and any(.detail.seal_defects[]; .row == \"Paper.Example\" and .seal == \"seal-failed\")"
as_student git reset -q --hard "$ACTIVE"

# B6 CANARY E2E-PARTIAL: the same sorry under the partial row: no lean defect (a non-claiming row's failed seal is not
#    a defect), but the required lean edge is broken, so exit 1 through the verdicts
write_sorry
gcommit -am "canary: sorry, partial"
check_run E2E-PARTIAL 1 --build --onearch "$ONEARCH"
jcheck E2E-PARTIAL "$LEAN | .status == \"clean\""
jcheck E2E-PARTIAL "$(ROW Paper.Example) == \"seal-failed\""
jcheck E2E-PARTIAL '[.statements[] | select(.stmt | endswith(":Lem-Example"))][0].verdicts.lean == "broken"'
as_student git reset -q --hard "$ACTIVE"

# B7 CANARY E2E-FORGE: a theorem on an axiom of its own module, behind a macro that makes `#print axioms` lie, in a
#    row claiming machine-checked: the seal replays the proof through the kernel and fails it, exit 1 (S1 inside
#    ias-check)
as_student sh -c 'cat > lean/Paper/Forge.lean' <<'EOF'
/-
SPDX-License-Identifier: Apache-2.0
CANARY E2E-FORGE (the image test): `forged` rests on an axiom of this module, and the macro below makes every later
`#print axioms X` claim that X depends on no axioms. A seal that reads `#print axioms` is fooled; ias-check's seal
replays the proof through the kernel and must fail it.
-/
import Lean

namespace Paper.Forge

axiom fake : (2 : Nat) + 2 = 5

theorem forged : (2 : Nat) + 2 = 5 := fake

end Paper.Forge

macro_rules
  | `(#print axioms $x:ident) =>
    `(#eval IO.println ("'" ++ $(Lean.Syntax.mkStrLit (toString x.getId)) ++ "' does not depend on any axioms"))

#print axioms Paper.Forge.forged
EOF
as_student sh -c 'printf "import Paper.Example\nimport Paper.Forge\n" > lean/Paper.lean'
as_student sh -c 'jq ".nodes += [{\"id\": \"Paper.Forge\", \"label\": \"CANARY E2E-FORGE: a theorem on an axiom of its own\", \"verifies\": [], \"cert\": {\"module\": \"Paper.Forge\", \"theorems\": [\"Paper.Forge.forged\"], \"status\": \"machine-checked\"}}]" lean/ledger.json > lean/ledger.json.new && mv lean/ledger.json.new lean/ledger.json'
as_student git add lean/Paper/Forge.lean
gcommit -am "canary: forge"
check_run E2E-FORGE 1 --build --require-complete --onearch "$ONEARCH"
jcheck E2E-FORGE "$LEAN | .status == \"defects\" and any(.detail.seal_defects[]; .row == \"Paper.Forge\" and .seal == \"seal-failed\")"
as_student git reset -q --hard "$ACTIVE"

# B10 THE ENTRYPOINT (one run line on every OS, no --user flag)
# (a) a repository owned by a non-root uid (Linux, macOS): the run is that uid's, and the toolchain is read-only for it
chown -R 4343:4343 "$R"
rm -f check-report.json
rc=0; "$EP" ias-check run --build --require-complete --onearch "$ONEARCH" > "$T/page.txt" 2>&1 || rc=$?
[ "$rc" = 0 ] || { cat "$T/page.txt" >&2; fail "B10 OWNER: the entrypoint's run exited $rc (expected 0)"; }
[ "$(stat -c %u check-report.json)" = 4343 ] || fail "B10 OWNER: the report is not owned by the folder's owner (4343)"
jcheck "B10 OWNER" "$LEAN | .detail.toolchain_writable == false"
chown -R $U:$U "$R"
# (b) a root-owned folder anyone may write (a Windows drive): uid 4242; (c) a root-only folder: root;
# (d) started as non-root (--user, --userns=keep-id): the command runs as given
mkdir "$T/w" "$T/r"
chmod 0777 "$T/w"
chmod 0755 "$T/r"
[ "$(cd "$T/w" && "$EP" id -u)" = 4242 ] || fail "B10 ROOT-OWNED, WRITABLE: the entrypoint did not run as 4242"
[ "$(cd "$T/w" && "$EP" id -g)" = 4242 ] || fail "B10 ROOT-OWNED, WRITABLE: the entrypoint did not run as group 4242"
[ "$(cd "$T/r" && "$EP" id -u)" = 0 ] || fail "B10 ROOT-ONLY: the entrypoint did not stay root"
[ "$(cd "$T/r" && setpriv --reuid=4545 --regid=4545 --clear-groups "$EP" id -u)" = 4545 ] \
  || fail "B10 NON-ROOT START: the entrypoint changed the uid it was started with"
cd "$R"

# B11 THE NOTICE's listing: tlmgr names every installed TeX Live package with its catalogue licence, offline
tlmgr info --only-installed --data name,cat-license > "$T/licences.txt" 2>&1 \
  || { tail -n 20 "$T/licences.txt" >&2; fail "B11: tlmgr cannot list the installed packages' licences"; }
grep -q '^luaotfload,' "$T/licences.txt" || fail "B11: the licence listing does not name luaotfload"

# B8 ELAN-RO and THE CACHE RULE: after every uid-4242 build above, nothing under /opt/elan or /opt/texlive changed.
#    luaotfload reads and writes its names database ONLY at the first WRITABLE TEXMFCACHE path (the Dockerfile's tex
#    stage names the source lines and the version it was read at): the image's database, built as root, is in
#    TEXMFSYSVAR and serves root's runs; a non-root uid's first writable path is TEXMFVAR=/tmp/texmf-var, where its
#    first lualatex run builds its own. So (a) the image's database exists, (b) the uid's database exists under its
#    TEXMFVAR (the runs above reached luaotfload), and (c) no luaotfload cache was written under the test's folders
ch="$(find /opt/elan /opt/texlive -newer "$T/stamp" | head -n 5)"
[ -z "$ch" ] || fail "B8 ELAN-RO: the toolchains changed during the student's runs: $ch"
as_student luaotfload-tool --version 2>&1 | sed 's/^/B8: /'
sv="$(kpsewhich -var-value TEXMFSYSVAR)"
[ -n "$(find "$sv/luatex-cache/generic/names" -name 'luaotfload-names*' 2> /dev/null | head -n 1)" ] \
  || fail "B8 IMAGE-DB: no luaotfload names database under $sv/luatex-cache/generic/names (the tex stage's luaotfload-tool --update)"
[ -n "$(find /tmp/texmf-var/luatex-cache/generic/names -name 'luaotfload-names*' 2> /dev/null | head -n 1)" ] \
  || fail "B8 UID-DB: no luaotfload names database under /tmp/texmf-var: the uid-$U runs never reached luaotfload, or it wrote elsewhere"
lc="$(find "$T" -path '*luatex-cache*' | head -n 5)"
[ -z "$lc" ] || fail "B8 NO-LEAK: a luaotfload cache was written under the test's folders: $lc"

# B9 ROOT (the cost of staying root, pinned): root sees the toolchain writable (access(2)), so --build alone exits 0 with
#    toolchain_writable true and the note, and --require-complete makes it a lean defect, exit 1
rc=0; ias-check run --build --onearch "$ONEARCH" > "$T/page.txt" 2>&1 || rc=$?
[ "$rc" = 0 ] || { cat "$T/page.txt" >&2; fail "B9 ROOT: --build as root exited $rc (expected 0)"; }
jcheck "B9 ROOT" "$LEAN | .detail.toolchain_writable == true"
jcheck "B9 ROOT" 'any(.notes[]; startswith("toolchain-writable:"))'
rc=0; ias-check run --build --require-complete --onearch "$ONEARCH" > "$T/page.txt" 2>&1 || rc=$?
[ "$rc" = 1 ] || { cat "$T/page.txt" >&2; fail "B9 ROOT: --build --require-complete as root exited $rc (expected 1)"; }

mkdir -p "$MARK"
echo "1arch-tools-build test OK: 1Arch $(cat "$ONEARCH/ONEARCH_COMMIT" 2> /dev/null || echo unknown), $(lean --version | head -n 1), $(lualatex --version | head -n 1), $(uname -m)" \
  > "$MARK/test-passed"
cd /
rm -rf "$T"
echo "test OK"
