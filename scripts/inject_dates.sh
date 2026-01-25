#!/usr/bin/env bash
set -euo pipefail

POSTS_DIR="content/posts"

find "$POSTS_DIR" -type f -name "*.md" | while read -r file; do
  base="$(basename "$file")"

  if [[ "$base" == _* ]]; then
    continue
  fi

  if ! grep -q '^date *= *' "$file"; then
    ts=$(git log --follow --reverse --format=%aI -- "$file" | head -n 1)


    if [[ -z "$ts" ]]; then
      echo "No git history for $file, skipping"
      continue
    fi

    echo "Injecting date $ts into $file"

    # insert date after front-matter opening +++
    awk -v date="$ts" '
      BEGIN { inserted=0 }
      /^(\+\+\+|---)$/ && inserted==0 {
        print
        print "date = " date
        inserted=1
        next
      }
      { print }
    ' "$file" > "$file.tmp"

    mv "$file.tmp" "$file"
  fi
done
