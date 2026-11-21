# SPDX-License-Identifier: Apache-2.0
# install-tl profile for the 1arch-tools:<release>-build image: scheme-basic only; the Dockerfile adds the rest with tlmgr. The binaries
# are the platform install-tl detects (x86_64-linux or aarch64-linux).
selected_scheme scheme-basic
TEXDIR /opt/texlive/2023
TEXMFLOCAL /opt/texlive/texmf-local
TEXMFSYSCONFIG /opt/texlive/2023/texmf-config
TEXMFSYSVAR /opt/texlive/2023/texmf-var
TEXMFHOME ~/texmf
TEXMFCONFIG ~/.texlive2023/texmf-config
TEXMFVAR ~/.texlive2023/texmf-var
instopt_adjustpath 0
instopt_adjustrepo 0
instopt_letter 0
instopt_portable 0
instopt_write18_restricted 1
tlpdbopt_autobackup 0
tlpdbopt_create_formats 1
tlpdbopt_generate_updmap 0
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
tlpdbopt_post_code 1
