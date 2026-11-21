#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VakeWorks AB
#
# 1arch-entrypoint -- one run line on Linux, macOS and Windows, with no --user flag. The container starts as root;
# this runs the command as the owner of the folder it runs in (the mounted group repository), so what the command
# writes belongs to the student, and the image's Lean and TeX stay read-only for the run (ias-check's
# toolchain_writable is false).
#   - started as non-root (docker run --user ..., podman run --userns=keep-id): the command runs as given;
#   - the folder belongs to a non-root uid (Linux, macOS): the command runs as that uid;
#   - the folder belongs to root (a Windows drive, some shared folders): as uid 4242, if 4242 can write it;
#   - otherwise (a folder only root may write): as root, and ias-check reports the toolchain writable.
# A dropped uid has no passwd entry, so HOME is /tmp; ELAN_HOME, PATH and TEXMFVAR come from the image.
set -eu
[ "$(id -u)" = 0 ] || exec "$@"
uid="$(stat -c %u .)"
gid="$(stat -c %g .)"
if [ "$uid" = 0 ]; then
  if setpriv --reuid=4242 --regid=4242 --clear-groups test -w .; then
    uid=4242
    gid=4242
  else
    exec "$@"
  fi
fi
# never the root group for a dropped uid
[ "$gid" != 0 ] || gid="$uid"
exec setpriv --reuid="$uid" --regid="$gid" --clear-groups env HOME=/tmp "$@"
