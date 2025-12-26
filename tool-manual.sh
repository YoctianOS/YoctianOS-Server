#!/usr/bin/env bash
set -euo pipefail

# tool-manual.sh
# Ask the user for a directory, keep only the newest .deb per package
# (supports numeric, DEV-*, git-* versions), regenerate APT metadata,
# and sign the Release file when possible.

# Requirements: bash 4+, dpkg-deb, dpkg, dpkg-scanpackages, apt-ftparchive, gzip.
# gpg is optional.

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

normalize_version() {
  local v="$1"
  if [[ -z "$v" ]]; then
    printf ''
    return
  fi
  case "$v" in
    [0-9]*) printf '%s' "$v" ;;
    DEV*|dev*) printf '0~%s' "$v" ;;
    git*|GIT*) printf '0~%s' "$v" ;;
    *) printf '0~%s' "$v" ;;
  esac
}

extract_version_from_filename() {
  local fname="$1"
  local base="${fname%.deb}"
  if [[ "$base" =~ _([^_]+)_[^_]+$ ]]; then printf '%s' "${BASH_REMATCH[1]}"; return; fi
  if [[ "$base" =~ -([0-9A-Za-z.+~:]+)$ ]]; then printf '%s' "${BASH_REMATCH[1]}"; return; fi
  if [[ "$base" =~ (git[-_]r[0-9]+) ]]; then printf '%s' "${BASH_REMATCH[1]}"; return; fi
  printf ''
}

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

  declare -A best_file best_version_cmp
  local unreadable=()

  for f in "${debs[@]}"; do
    [ -f "$f" ] || continue
    local pkg ver_raw
    pkg="$(dpkg-deb -f "$f" Package 2>/dev/null || true)"
    ver_raw="$(dpkg-deb -f "$f" Version 2>/dev/null || true)"

    if [ -z "$pkg" ] || [ -z "$ver_raw" ]; then
      ver_raw="$(extract_version_from_filename "$f")"
      if [ -z "$pkg" ]; then
        if [[ "$f" =~ ^([^_]+)_ ]]; then
          pkg="${BASH_REMATCH[1]}"
        else
          pkg="${f%%-*}"
          pkg="${pkg%.deb}"
        fi
      fi
      if [ -z "$ver_raw" ]; then
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

# --- User interaction -------------------------------------------------------
read -rp "Enter the path to your Debian package directory: " TARGET_DIR
if [ ! -d "$TARGET_DIR" ]; then
  echo "Directory does not exist: $TARGET_DIR"
  exit 1
fi

read -rp "You entered '$TARGET_DIR'. Are you sure you want to proceed? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Operation cancelled."
  exit 0
fi

cleanup_keep_latest_by_package "$TARGET_DIR"

cd "$TARGET_DIR" || exit

shopt -s nullglob
debs=( *.deb )
shopt -u nullglob
if [ "${#debs[@]}" -eq 0 ]; then
  echo "No .deb files remain after cleanup. Exiting."
  exit 0
fi

echo "Generating Packages..."
dpkg-scanpackages . /dev/null > Packages
gzip -9 -c Packages > Packages.gz

echo "Generating Release..."
apt-ftparchive release . > Release

echo "Signing Release (InRelease)..."
if command -v gpg >/dev/null 2>&1; then
  if ! gpg --batch --yes --clearsign -u "$GPG_KEY" -o InRelease Release 2>/dev/null; then
    echo "Warning: gpg clearsign failed. Attempting detached signature..."
    if gpg --batch --yes -u "$GPG_KEY" --output Release.gpg --detach-sign Release 2>/dev/null; then
      echo "Detached signature Release.gpg created."
    else
      echo "Warning: detached signing also failed; repository will be unsigned."
    fi
  fi
else
  echo "Warning: gpg not found; skipping signing."
fi

echo "Repository metadata generated successfully in: $TARGET_DIR"

