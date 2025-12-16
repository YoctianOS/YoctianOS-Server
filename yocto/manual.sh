#!/bin/bash

# Prompt for directory
read -rp "Enter the path to your Debian package directory: " TARGET_DIR

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
  echo "Directory does not exist: $TARGET_DIR"
  exit 1
fi

# Confirm with user
read -rp "You entered '$TARGET_DIR'. Are you sure you want to proceed? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Operation cancelled."
  exit 0
fi

# Change to target directory
cd "$TARGET_DIR" || exit

# Generate Packages and Packages.gz
dpkg-scanpackages . /dev/null > Packages
gzip -9 < Packages > Packages.gz

# Generate Release file
apt-ftparchive release . > Release

# Sign the Release file (update if needed)
gpg --clearsign -u "" -o InRelease Release

echo "Repository metadata generated successfully in: $TARGET_DIR"
