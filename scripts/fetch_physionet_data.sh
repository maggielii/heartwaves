#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/data/sources/physionet_manifest.json"
OUT_BASE="$ROOT_DIR/data/raw/physionet"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required to parse manifest JSON." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi

mkdir -p "$OUT_BASE"

echo "Reading manifest: $MANIFEST"

while IFS=$'\t' read -r dataset_id base_url; do
  [[ -z "${dataset_id:-}" ]] && continue
  target_dir="$OUT_BASE/$dataset_id"
  mkdir -p "$target_dir"

  echo
  echo "==> $dataset_id"
  echo "URL: $base_url"
  files_url="${base_url/content/files}"

  curl -fsSL "$base_url" -o "$target_dir/index.html" || {
    echo "Failed: $base_url" >&2
    continue
  }
  if curl -fsSL "$files_url" -o "$target_dir/files_index.html" 2>/dev/null; then
    grep -o 'href="[^"]*"' "$target_dir/files_index.html" \
      | sed -E 's/^href="(.*)"$/\1/' \
      | sed '/^\.\.$/d' \
      | sed '/^\.\.\/$/d' \
      > "$target_dir/FILES.txt" || true
    echo "Fetched: FILES.txt (from files index)"
  else
    echo "Skipped: FILES.txt (files index not present)"
  fi

  for extra in RECORDS RECORDS.gz SHA256SUMS SHA256SUMS.txt LICENSE LICENSE.txt README README.txt; do
    if curl -fsSL "${files_url}${extra}" -o "$target_dir/$extra" 2>/dev/null; then
      echo "Fetched: $extra (files)"
    elif curl -fsSL "${base_url}${extra}" -o "$target_dir/$extra" 2>/dev/null; then
      echo "Fetched: $extra (content)"
    else
      echo "Skipped: $extra (not present)"
    fi
  done
done < <(
  ruby -rjson -e '
    m = JSON.parse(File.read(ARGV[0]))
    m.fetch("datasets").each do |d|
      puts "#{d.fetch("id")}\t#{d.fetch("base_url")}"
    end
  ' "$MANIFEST"
)

echo
echo "Done. Files saved under: $OUT_BASE"
echo "Next: inspect each dataset directory and choose per-dataset parsers."
