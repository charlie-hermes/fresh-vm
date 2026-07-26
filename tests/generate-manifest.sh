#!/bin/bash
set -Eeuo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
while IFS= read -r -d '' file; do
  test "$file" = MANIFEST.sha256 && continue
  printf '%s  ./%s\n' "$(sha256sum "$file" | awk '{print $1}')" "$file"
done < <(git ls-files -z | LC_ALL=C sort -z)
