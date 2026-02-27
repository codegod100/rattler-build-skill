#!/bin/bash

# Simple script to generate a rattler-build recipe for a git repository

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <url> [--name <name>] [--version <version>] [--rev <rev>] [--output <output>]"
    exit 1
fi

URL=$1
shift

NAME=$(basename "$URL" .git)
VERSION="0.1.0"
REV="main"
OUTPUT="recipe.yaml"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --name) NAME="$2"; shift ;;
        --version) VERSION="$2"; shift ;;
        --rev) REV="$2"; shift ;;
        --output) OUTPUT="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

cat <<EOF > "$OUTPUT"
package:
  name: $NAME
  version: $VERSION

source:
  git: $URL
  rev: $REV

build:
  number: 0
  script:
    - "# Add your build script here"
    - "# For python: python -m pip install . --no-deps -vv"

requirements:
  host:
    - python
    - pip
  run:
    - python

tests:
  - script:
      - "# Add test commands here"
      - "python -c \"import ${NAME//-/_}\""

about:
  summary: Recipe for $NAME
  repository: $URL
EOF

echo "Generated recipe in $OUTPUT"
