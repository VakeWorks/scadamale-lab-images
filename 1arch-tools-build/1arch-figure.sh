#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VakeWorks AB
#
# 1arch-figure -- turn TikZ figures into PNG images for your slides, the way the course's lecture figures are made:
# the tikzpicture in each .tex file is set on a page of its own with lualatex, then rasterised at 220 dpi.
#
#   1arch-figure slides/figures/fig-flow.tex [more.tex ...]   writes slides/assets/fig-flow.png, ...
#   1arch-figure -o <dir> slides/figures/fig-flow.tex         writes <dir>/fig-flow.png
#
# Then put it on a slide:  ![w:600](assets/fig-flow.png)   and build with  marp --html --allow-local-files ...
#
# A figure file holds one tikzpicture. Anything around it is ignored (a \resizebox, a \begin{figure}), so the same
# file can also be \input in your paper. The page loads tikz (libraries arrows.meta and fit), amsmath and amssymb,
# plus every \usetikzlibrary{...} line found in the file. Nothing is fetched; the work happens in a temporary folder.
# Exit 0 when every figure was made, 1 when one failed (its log tail is printed), 2 on a usage error.
set -eu
out=slides/assets
if [ "${1:-}" = "-o" ]; then
  [ -n "${2:-}" ] || { echo "usage: 1arch-figure [-o <dir>] <figure.tex> ..." >&2; exit 2; }
  out="$2"; shift 2
fi
[ $# -gt 0 ] || { echo "usage: 1arch-figure [-o <dir>] <figure.tex> ..." >&2; exit 2; }
for c in perl lualatex pdftoppm; do
  command -v "$c" > /dev/null || { echo "1arch-figure: $c is missing (run it in the 1arch-tools -build image)" >&2; exit 2; }
done
mkdir -p "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rc=0
for f in "$@"; do
  [ -f "$f" ] || { echo "MISSING $f" >&2; rc=1; continue; }
  name="$(basename "$f" .tex)"
  # the tikzpicture, from its first \begin to its last \end (as the lecture route takes it), and the file's own
  # \usetikzlibrary lines
  if ! perl -0777 -ne 'exit 3 unless /(\\begin\{tikzpicture\}.*\\end\{tikzpicture\})/s; print $1' "$f" > "$work/$name.body"; then
    echo "FAIL $f: no tikzpicture in it" >&2; rc=1; continue
  fi
  perl -ne 'print if /^\s*\\usetikzlibrary\{[^}]*\}\s*$/' "$f" > "$work/$name.libs"
  {
    printf '%s\n' '\documentclass[border=6pt]{standalone}'
    printf '%s\n' '\usepackage{tikz}\usetikzlibrary{arrows.meta,fit}'
    cat "$work/$name.libs"
    printf '%s\n' '\usepackage{amsmath,amssymb}' '\begin{document}'
    cat "$work/$name.body"
    printf '\n%s\n' '\end{document}'
  } > "$work/$name.tex"
  if ! ( cd "$work" && lualatex -interaction=nonstopmode -halt-on-error -no-shell-escape "$name.tex" > "$name.buildlog" 2>&1 ); then
    echo "FAIL $f: lualatex stopped; the end of its log:" >&2
    tail -n 20 "$work/$name.buildlog" >&2
    rc=1; continue
  fi
  pdftoppm -png -r 220 -singlefile "$work/$name.pdf" "$out/$name"
  echo "OK   $f -> $out/$name.png"
done
exit $rc
