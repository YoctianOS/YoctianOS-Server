#!/usr/bin/env bash
set -euo pipefail

# tool-auto.sh
# Scan the tree for directories containing .deb files, keep only the newest .deb
# per package (supports numeric, DEV-*, git-* versions), regenerate APT metadata,
# and sign the Release file when possible.

# Requirements: bash 4+, dpkg-deb, dpkg, dpkg-scanpackages, apt-ftparchive, gzip.
# gpg is optional (falls back to detached signature).

# --- Preconditions ----------------------------------------------------------
if ((BASH_VERSINFO[0] < 4)); then
  echo "Error: this script requires bash 4 or newer." >&2
  exit 1
fi

required_cmds=(dpkg-deb dpkg dpkg-scanpackages apt-ftparchive gzip)
for cmd in "${required_cmds[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found. Install it and retry." >&2
    exit 1
  fi
done

# GPG key ID (update if needed)
GPG_KEY=""

# Find directories containing .deb files
DEB_DIRS=$(find . -type f -name "*.deb" -printf '%h\n' | sort -u)

# --- Helpers ----------------------------------------------------------------

# Normalize a version string so dpkg --compare-versions can compare it.
# Numeric versions are returned unchanged. Non-numeric versions are prefixed
# with "0~" so they compare consistently.
normalize_version() {
  local v="$1"
  if [[ -z "$v" ]]; then
    printf ''
    return
  fi
  case "$v" in
    [0-9]*)
      printf '%s' "$v"
      ;;
    DEV*|dev*|git*|GIT*)
      printf '0~%s' "$v"
      ;;
    *)
      printf '0~%s' "$v"
      ;;
  esac
}

# Try to extract a plausible version from the filename (best-effort).
extract_version_from_filename() {
  local fname="$1"
  local base="${fname%.deb}"
  if [[ "$base" =~ _([^_]+)_[^_]+$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$base" =~ -([0-9A-Za-z.+~:]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$base" =~ (git[-_]r[0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  printf ''
}

# Keep only the newest .deb per Package in the given directory.
cleanup_keep_latest_by_package() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    return 0
  fi
  echo "Cleaning directory: $dir"
  pushd "$dir" > /dev/null || return 0

  shopt -s nullglob
  local debs=( *.deb )
  shopt -u nullglob

  if [ "${#debs[@]}" -eq 0 ]; then
    echo "  No .deb files found in $dir"
    popd > /dev/null || true
    return 0
  fi

  declare -A best_file
  declare -A best_version_cmp
  local unreadable=()

  # First pass: determine newest per package
  for f in "${debs[@]}"; do
    [ -f "$f" ] || continue

    local pkg
    local ver_raw
    pkg="$(dpkg-deb -f "$f" Package 2>/dev/null || true)"
    ver_raw="$(dpkg-deb -f "$f" Version 2>/dev/null || true)"

    if [ -z "$pkg" ] || [ -z "$ver_raw" ]; then
      # try filename heuristics
      local ver_from_name
      ver_from_name="$(extract_version_from_filename "$f")"
      if [ -n "$ver_from_name" ]; then
        ver_raw="$ver_from_name"
        if [ -z "$pkg" ]; then
          # best-effort package guess from filename
          if [[ "$f" =~ ^([^_]+)_ ]]; then
            pkg="${BASH_REMATCH[1]}"
          else
            pkg="${f%%-*}"
            pkg="${pkg%.deb}"
          fi
        fi
      else
        unreadable+=("$f")
        continue
      fi
    fi

    if [ -z "$pkg" ] || [ -z "$ver_raw" ]; then
      continue
    fi

    local ver_cmp
    ver_cmp="$(normalize_version "$ver_raw")"

    if [ -z "${best_version_cmp[$pkg]:-}" ] || dpkg --compare-versions "$ver_cmp" gt "${best_version_cmp[$pkg]}"; then
      best_version_cmp[$pkg]="$ver_cmp"
      best_file[$pkg]="$f"
    fi
  done

  # Second pass: remove older files
  local removed=0
  for f in "${debs[@]}"; do
    [ -f "$f" ] || continue
    local pkg
    pkg="$(dpkg-deb -f "$f" Package 2>/dev/null || true)"
    if [ -z "$pkg" ]; then
      if [[ "$f" =~ ^([^_]+)_ ]]; then
        pkg="${BASH_REMATCH[1]}"
      else
        pkg="${f%%-*}"
        pkg="${pkg%.deb}"
      fi
    fi
    [ -z "$pkg" ] && continue
    local keep="${best_file[$pkg]:-}"
    if [ -n "$keep" ] && [ "$f" != "$keep" ]; then
      echo "  Removing: '$f' (keeping '$keep')"
      rm -f -- "$f" && removed=$((removed+1))
    fi
  done

  echo "  Cleanup complete for $dir. Files removed: $removed"

  if [ "${#unreadable[@]}" -gt 0 ]; then
    local max_show=8
    if [ "${#unreadable[@]}" -le "$max_show" ]; then
      printf "  Note: %d file(s) skipped (could not read metadata): %s\n" "${#unreadable[@]}" "$(printf '%s ' "${unreadable[@]}")"
    else
      local first_list
      first_list="$(printf '%s ' "${unreadable[@]:0:$max_show}")"
      local remaining=$(( ${#unreadable[@]} - max_show ))
      printf "  Note: %d file(s) skipped (could not read metadata). Examples: %s... (+%d more)\n" "${#unreadable[@]}" "$first_list" "$remaining"
    fi
    echo "  These files were left untouched."
  fi

  unset best_file best_version_cmp
  popd > /dev/null || true
}

# --- Main loop --------------------------------------------------------------
if [ -z "${DEB_DIRS:-}" ]; then
  echo "No .deb files found. Nothing to do."
  exit 0
fi

OLD_IFS="$IFS"
IFS=$'\n'
for TARGET_DIR in $DEB_DIRS; do
  [ -z "$TARGET_DIR" ] && continue
  if [ ! -d "$TARGET_DIR" ]; then
    echo "Skipping missing directory: $TARGET_DIR"
    continue
  fi

  cleanup_keep_latest_by_package "$TARGET_DIR"

  pushd "$TARGET_DIR" > /dev/null || continue

  shopt -s nullglob
  debs=( *.deb )
  shopt -u nullglob
  if [ "${#debs[@]}" -eq 0 ]; then
    echo "  No .deb files remain in $TARGET_DIR after cleanup, skipping metadata generation."
    popd > /dev/null || true
    continue
  fi

  echo "  Generating Packages..."
  dpkg-scanpackages . /dev/null > Packages
  gzip -9 -c Packages > Packages.gz

  echo "  Generating Release..."
  apt-ftparchive release . > Release

  echo "  Signing Release (InRelease)..."
  if command -v gpg >/dev/null 2>&1; then
    if ! gpg --batch --yes --clearsign -u "$GPG_KEY" -o InRelease Release 2>/dev/null; then
      echo "  Warning: gpg clearsign failed. Attempting detached signature..."
      if gpg --batch --yes -u "$GPG_KEY" --output Release.gpg --detach-sign Release 2>/dev/null; then
        echo "  Detached signature Release.gpg created."
      else
        echo "  Warning: detached signing also failed; repository will be unsigned."
      fi
    fi
  else
    echo "  Warning: gpg not found; skipping signing."
  fi

  echo "Repository metadata generated in: $TARGET_DIR"
  popd > /dev/null || exit
done
IFS="$OLD_IFS"

