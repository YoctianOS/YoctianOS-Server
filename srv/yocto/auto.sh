#!/bin/bash

# Find all unique directories containing .deb files
DEB_DIRS=$(find . -type f -name "*.deb" -printf '%h\n' | sort -u)

# GPG key ID (update if needed)
GPG_KEY=""

# Loop through each directory
for TARGET_DIR in $DEB_DIRS; do
  echo "Processing directory: $TARGET_DIR"

  cd "$TARGET_DIR" || continue

  # Generate Packages and Packages.gz
  dpkg-scanpackages . /dev/null > Packages
  gzip -9 < Packages > Packages.gz

  # Generate Release file
  apt-ftparchive release . > Release

  # Sign the Release file (optional)
  gpg --clearsign -u "$GPG_KEY" -o InRelease Release

  echo "Repository metadata generated in: $TARGET_DIR"
  cd - > /dev/null || exit
done

