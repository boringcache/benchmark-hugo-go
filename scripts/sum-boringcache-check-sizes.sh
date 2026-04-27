#!/usr/bin/env bash
set -euo pipefail

workspace="${1:-}"
tags_csv="${2:-}"

if [[ -z "$workspace" || -z "$tags_csv" ]]; then
  echo "0"
  exit 0
fi

tmp_file="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$tmp_file" "$stderr_file"' EXIT

# Check all tags in one request so tag resolution/miss accounting is consistent.
if ! boringcache check "$workspace" "$tags_csv" --no-git --no-platform --exact --json > "$tmp_file" 2> "$stderr_file"; then
  echo "boringcache check failed while measuring remote storage for tags: ${tags_csv}" >&2
  cat "$stderr_file" >&2
  exit 1
fi

if ! jq -e '.results | type == "array"' "$tmp_file" >/dev/null 2>&1; then
  echo "boringcache check returned unexpected JSON while measuring remote storage" >&2
  cat "$tmp_file" >&2
  exit 1
fi

miss_count="$(
  jq -r '
    [
      .results[]?
      | select((.status // "") != "hit")
    ] | length
  ' "$tmp_file"
)"

if [[ "$miss_count" != "0" ]]; then
  echo "warning: boringcache check did not find every expected storage tag: ${tags_csv}" >&2
  jq -r '.results[]? | "\(.tag // .entry // "unknown"): \(.status // "unknown")"' "$tmp_file" >&2
  if [[ -n "${BORINGCACHE_STORAGE_MISSING_PATH:-}" ]]; then
    jq -r '
      .results[]?
      | select((.status // "") != "hit")
      | .tag // .requested_tag // .requestedTag // "unknown"
    ' "$tmp_file" > "$BORINGCACHE_STORAGE_MISSING_PATH"
  fi
fi

to_num() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo "0"
  fi
}

declare -A seen_entries=()
total=0

while IFS= read -r row; do
  [[ -n "$row" ]] || continue

  key="$(jq -r '.cache_entry_id // .cacheEntryId // .manifest_root_digest // .manifestRootDigest // .requested_tag // .requestedTag // .tag // "unknown"' <<<"$row")"
  tag="$(jq -r '.tag // .requested_tag // .requestedTag // empty' <<<"$row")"
  size="$(jq -r '.compressed_size // .compressedSize // .size_bytes // .sizeBytes // .size // 0' <<<"$row")"
  size="$(to_num "$size")"

  if [[ "$size" == "0" && -n "$tag" ]]; then
    inspect_json="$(boringcache inspect "$workspace" "$tag" --json 2> "$stderr_file" || true)"
    if [[ -n "$inspect_json" ]]; then
      inspect_key="$(jq -r '.entry.id // empty' <<<"$inspect_json" 2>/dev/null || true)"
      if [[ -n "$inspect_key" ]]; then
        key="$inspect_key"
      fi
      inspected_size="$(jq -r '.entry.stored_size_bytes // .entry.compressed_size // .entry.archive_size // .entry.blob_total_size_bytes // .entry.uncompressed_size // 0' <<<"$inspect_json" 2>/dev/null || true)"
      size="$(to_num "$inspected_size")"
    else
      echo "boringcache inspect failed while measuring remote storage for tag: ${tag}" >&2
      cat "$stderr_file" >&2
      exit 1
    fi
  fi

  if [[ -z "${seen_entries[$key]+x}" ]]; then
    seen_entries[$key]=1
    total=$((total + size))
  fi
done < <(jq -c '.results[]? | select((.status // "") == "hit")' "$tmp_file")

if [[ -z "$total" || ! "$total" =~ ^[0-9]+$ ]]; then
  total=0
fi

echo "$total"
