#!/usr/bin/env bash

set -o errexit

OUTDIR=docs/modules/api/pages/

if [ ! -d node_modules ]; then
  npm ci
fi

rm -rf "$OUTDIR"
solidity-docgen -t docs -o "$OUTDIR" -x adoc -e contracts/mocks,contracts/examples
node scripts/gen-nav.js "$OUTDIR" > "$OUTDIR/../nav.adoc"
