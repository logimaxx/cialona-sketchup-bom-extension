#!/usr/bin/env bash
# Build a SketchUp .rbz: loader + extension folder at the archive root.
# SketchUp installs that pair into Plugins. Icon backups stay out.
# Dev mode follows the load path, so this installed copy does not enable it.
# A leftover DEV marker is not shipped.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
cd "$root"

version="$(sed -n 's/.*ex\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' cialona_bom_exporter.rb)"
if [[ -z "$version" ]]; then
  echo "version not found in cialona_bom_exporter.rb" >&2
  exit 1
fi

stamp="$(date +%Y%m%d)"
mkdir -p dist
n=1
while :; do
  suffix="$(printf '%s%02d' "$stamp" "$n")"
  out="dist/cialona_bom_exporter_${suffix}.rbz"
  [[ -e "$out" ]] || break
  n=$((n + 1))
done

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp cialona_bom_exporter.rb "$stage/"
mkdir -p "$stage/cialona_bom_exporter"
rsync -a \
  --exclude 'icons/backup/' \
  --exclude 'DEV' \
  --exclude '.DS_Store' \
  cialona_bom_exporter/ "$stage/cialona_bom_exporter/"

(
  cd "$stage"
  zip -r -q "$root/$out" cialona_bom_exporter.rb cialona_bom_exporter
)

echo "Built $out (extension version $version)"
