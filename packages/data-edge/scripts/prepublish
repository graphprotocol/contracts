#!/bin/bash

TYPECHAIN_DIR=dist/types

set -eo pipefail

# Build contracts
yarn clean
yarn build

# Refresh distribution folder
rm -rf dist && mkdir -p dist/types/_src
cp -R build/abis/ dist/abis
cp -R build/types/ dist/types/_src

### Build Typechain bindings

# Build and create TS declarations
tsc -d ${TYPECHAIN_DIR}/_src/*.ts --outdir ${TYPECHAIN_DIR}
# Copy back sources
cp ${TYPECHAIN_DIR}/_src/*.ts ${TYPECHAIN_DIR}
# Delete temporary src dir
rm -rf ${TYPECHAIN_DIR}/_src