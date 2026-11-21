# 1arch-tools:&lt;release&gt;-build

The 1ArchCodeMathsProveDog commands of one release (the `1arch-tools:<release>` image), plus core Lean 4.32.0,
TeX Live 2023 (LuaLaTeX, latexmk, BibTeX) and the course's slide tools (Marp with Node.js, and `1arch-figure` for
TikZ figures). With it, `ias-check run --build` runs in one container: it builds your paper's PDF, and builds your
Lean project and seals its theorems. Your talk (as a web page) and its figures build in the same container, the way
the course's lecture slides are built; the image has no web browser, so the talk's PDF is made on your own machine
(below). It carries no code runner (no sbt or JDK, cabal or pytest): when your repository has an active code spine,
run its tests with your own tools.

- `1arch-tools:<release>` is the light image: `ias-check run` without `--build`.
- `1arch-tools:<release>-build` is this image: the same commands, plus Lean, TeX and the slide tools. It is larger,
  so pull it when you build.
- Both tags name the same release. A tag never moves.
- One image serves Intel/AMD and ARM machines.

## Run it

You need Docker (Docker Desktop on macOS and Windows; Docker or Podman on Linux). Define the command once per
shell, then run it from the root of your group's repository, after a commit:

```
alias onearch='docker run --rm -v "$PWD":/work -w /work docker.io/vakeworks/1arch-tools:<release>-build'
onearch ias-check run --build
```

- Windows, PowerShell:
  `function onearch { docker run --rm -v "${PWD}:/work" -w /work docker.io/vakeworks/1arch-tools:<release>-build @args }`.
  In cmd.exe the mount is `-v "%cd%:/work"`. With WSL2, keep the repository inside WSL's own file system (`~/...`).
- Rootless Podman on Linux: `podman run --rm --userns=keep-id ...` in place of `docker run --rm ...`.
- No `--user` flag is needed on any system. The image starts as root, then runs your command as the owner of the
  folder you mounted, so the files it writes are yours. If that owner is root (a Windows drive, for example), it
  runs as uid 4242 when that uid may write the folder; otherwise it stays root. Lean and TeX are read-only for
  your run, which is what `ias-check` checks before it seals your theorems.

## Build only the paper

A group that does not use the check can still build its paper the way the check does. In the `paper/` folder, with
`preamble.tex`, `ias-symbol-macros.sty`, `refs.bib` and `figures/` beside `main.tex`:

```
cd paper
onearch latexmk -norc -lualatex -bibtex -interaction=nonstopmode -halt-on-error -file-line-error -no-shell-escape main.tex
```

This gives `main.pdf`. It is exactly the line `ias-check run --build` runs (`-norc`: no latexmkrc is read).

## Build your slides and figures

The talk in `slides/` builds with the course theme, the way the course's lecture slides are built. In the container
it builds as a web page:

```
onearch marp --html --allow-local-files --theme slides/scadamale-marp-theme.css slides/talk.md
```

This gives `slides/talk.html`. Open it in your web browser to check or present the talk.

The PDF of the talk is made on your own machine, because Marp needs a web browser to print it and the image has none:

1. Install Node.js 22 (https://nodejs.org) and have Chrome, Edge or Firefox installed.
2. From the root of your repository, run:

   ```
   npx @marp-team/marp-cli@4.5.0 --html --allow-local-files --theme slides/scadamale-marp-theme.css slides/talk.md --pdf
   ```

3. This gives `slides/talk.pdf`. With `--images png` in place of `--pdf` you get one image per slide instead.
   Without `--allow-local-files`, the images in `slides/assets/` come out blank.

The same line without `--pdf` gives `slides/talk.html` too, so with Node.js you can build the slides without the
container.

A figure drawn in TikZ becomes a slide image with `1arch-figure`. Keep one `tikzpicture` per file, for example
`slides/figures/fig-flow.tex` (the same file can also be `\input` in your paper), then:

```
onearch 1arch-figure slides/figures/fig-flow.tex
```

This writes `slides/assets/fig-flow.png` (`-o <folder>` writes elsewhere); put it on a slide with
`![w:600](assets/fig-flow.png)`. The figure's page loads TikZ (with `arrows.meta` and `fit`), `amsmath` and `amssymb`,
plus each `\usetikzlibrary{...}` line in your file.

## What the image is tested for

Before an image is published, on each architecture, with no network:
- `ias-check run --build --require-complete` passes on a freshly made group repository, as a non-root user;
- three canaries fail as they must: a `sorry` under a row that claims machine-checked, the same `sorry` under a
  partial row, and a forged `#print axioms`;
- a paper written only on the template's files builds with the line above;
- Lean and TeX stay unchanged by the user's runs, and the font cache is already built;
- the entrypoint runs as the folder's owner, as described above;
- the template's talk builds to a web page with the container line above as a non-root user, with every slide of
  `talk.md`, in the course theme, and a TikZ figure made with `1arch-figure` shows on a slide;
- the image carries no web browser.

## Licences

See `NOTICE` (in the image: `/usr/share/doc/1arch-tools-build/NOTICE`): Apache-2.0 for VakeWorks' parts, and each
other part under its own licence. The full list of TeX Live packages and their licences:
`docker run --rm --entrypoint tlmgr docker.io/vakeworks/1arch-tools:<release>-build info --only-installed --data name,cat-license`.
