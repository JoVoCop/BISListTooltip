#!/usr/bin/env bash
# Copies the same file set the release workflow zips into <AddOns directory>/BISListTooltip.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <AddOns directory>" >&2
  exit 1
fi

addons_dir="$1"
if [ ! -d "$addons_dir" ]; then
  echo "Error: '$addons_dir' is not a directory" >&2
  exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="$addons_dir/BISListTooltip"

# Removing first keeps files deleted from the repo from lingering in the game folder.
rm -rf "$destination"
mkdir -p "$destination"
cp "$repo_dir"/BISListTooltip.toc "$repo_dir"/*.lua "$destination"/
cp -r "$repo_dir"/Data "$repo_dir"/Libs "$repo_dir"/Media "$destination"/
echo "Installed to $destination"
