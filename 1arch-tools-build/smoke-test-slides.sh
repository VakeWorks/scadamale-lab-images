#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VakeWorks AB
#
# smoke-test-slides.sh -- the -build image's slides test: the group template's talk built to HTML the way the
# course's lecture slides are built (Marp with --html and --allow-local-files, the course theme), and a TikZ figure
# made into a slide image with 1arch-figure, inside the image, on every architecture, with no network (the Dockerfile
# runs it RUN --network=none). The image carries no browser (the op's ruling (e), 2026-11-20): the PDF of a talk is
# made on the student's own machine, so nothing here claims one. Runs as root and makes the student's runs as uid
# 4242 through setpriv, as smoke-test-build.sh does. Exit 0 all held, and the marker slides-test-passed is written;
# 1 a named failure.
set -eu
MARK="${TEST_MARK_DIR:-/usr/local/share/1arch-tools-build}"
U=4242
fail() { echo "TEST FAIL: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail "run as root (the test switches to uid $U with setpriv)"
for c in setpriv node marp 1arch-figure lualatex pdftoppm; do
  command -v "$c" > /dev/null || fail "$c is missing"
done
as_student() { setpriv --reuid=$U --regid=$U --clear-groups env HOME=/tmp "$@"; }
T="$(mktemp -d)"
chmod 755 "$T"

# S0 THE TOOLS: Node 22; marp answers; and no browser in the image (ruling (e)), so nothing a student runs here
#    depends on one
v="$(node --version)"
case "$v" in v22.*) ;; *) fail "S0: node --version says '$v' (expected v22.*)" ;; esac
as_student marp --version > /dev/null 2>&1 || fail "S0: marp --version fails for uid $U"
[ -z "${CHROME_PATH:-}" ] || fail "S0: CHROME_PATH is set ('$CHROME_PATH'): the image must carry no browser"
for b in chrome chromium chromium-browser google-chrome google-chrome-stable firefox microsoft-edge; do
  if command -v "$b" > /dev/null; then fail "S0: a browser is on PATH: $(command -v "$b")"; fi
done

# THE TALK: the template's slides/ as a group has it, owned by uid 4242
[ -f "$ONEARCH/templates/group-project/slides/talk.md" ] \
  || fail "S1: this release's template has no slides/talk.md (build from a release that ships the template's slides)"
R="$T/repo"
mkdir -p "$R/out"
cp -r "$ONEARCH/templates/group-project/slides" "$R/slides"
chown -R $U:$U "$R"
cd "$R"
MARP="marp --html --allow-local-files --theme slides/scadamale-marp-theme.css"

# S1 THE HTML: the talk, as uid 4242, offline; an HTML page comes out and marp warns of nothing (an unknown theme is
#    a warning, not an error)
as_student $MARP slides/talk.md -o out/talk.html > "$T/s1.txt" 2>&1 \
  || { cat "$T/s1.txt" >&2; fail "S1: marp to HTML fails"; }
grep -qi '<!DOCTYPE html>' out/talk.html || fail "S1: out/talk.html is not an HTML page"
if grep -q 'WARN' "$T/s1.txt"; then cat "$T/s1.txt" >&2; fail "S1: marp warned"; fi

# S2 THE SLIDE COUNT: one slide <svg data-marpit-svg> per slide; the count is talk.md's own (its '---' lines, less
#    the front matter's two, plus one)
n=$(( $(grep -c '^---$' slides/talk.md) - 1 ))
got="$(grep -o '<svg[^>]*data-marpit-svg' out/talk.html | wc -l)"
[ "$got" = "$n" ] || fail "S2: $got slides in out/talk.html, talk.md has $n slides"

# S3 THE THEME APPLIED: the HTML carries the theme's own azure token, so the course theme, not Marp's default, rendered
grep -qi '#0e3a58' out/talk.html || fail "S3: the scadamale theme is not in the rendered HTML"

# S4 A FIGURE ON A SLIDE: a TikZ figure inside a \resizebox (as the course's figures are written), with a library
#    line of its own (positioning, carried over by 1arch-figure), made into slides/assets/fig-smoke.png by
#    1arch-figure as uid 4242, then a deck that shows it built to HTML. The PNG must not be blank: a figure that drew
#    nothing is cropped by standalone to its 6pt border, a PNG of a few hundred bytes, while this one's text and
#    lines at 220 dpi take several kilobytes
mkdir -p slides/figures
cat > slides/figures/fig-smoke.tex <<'EOF'
\usetikzlibrary{positioning}
\resizebox{0.6\linewidth}{!}{%
\begin{tikzpicture}[>=Stealth]
  \node[draw, rounded corners] (d) {data};
  \node[draw, rounded corners, right=2cm of d] (c) {claim $\forall x\,\varphi(x)$};
  \draw[->] (d) -- (c);
  \node[draw, dashed, fit=(d)(c)] {};
\end{tikzpicture}}
EOF
printf -- '---\nmarp: true\n---\n\n# A figure\n\n![w:600](assets/fig-smoke.png)\n' > slides/figure.md
chown -R $U:$U slides
as_student 1arch-figure slides/figures/fig-smoke.tex > "$T/s4a.txt" 2>&1 \
  || { cat "$T/s4a.txt" >&2; fail "S4: 1arch-figure fails"; }
[ "$(head -c 4 slides/assets/fig-smoke.png | tail -c 3)" = "PNG" ] || fail "S4: slides/assets/fig-smoke.png is not a PNG"
sz="$(wc -c < slides/assets/fig-smoke.png)"
[ "$sz" -ge 2048 ] || fail "S4: slides/assets/fig-smoke.png is $sz bytes (the figure came out blank)"
as_student $MARP slides/figure.md -o slides/figure.html > "$T/s4b.txt" 2>&1 \
  || { cat "$T/s4b.txt" >&2; fail "S4: marp to HTML of the figure deck fails"; }
grep -q 'assets/fig-smoke.png' slides/figure.html || fail "S4: slides/figure.html does not show the figure"

echo "1arch-tools slides test OK: $(node --version), marp $(marp --version 2>&1 | head -n 1), no browser, $(uname -m)" \
  > "$MARK/slides-test-passed"
echo "slides test OK"
