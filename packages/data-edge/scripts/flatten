#!/bin/bash

OUT_DIR="build/flatten"

mkdir -p ${OUT_DIR}

echo "Flattening contracts..."

FILES=(
    "contracts/Counter.sol"
)

for path in ${FILES[@]}; do
    IFS='/'
    parts=( $path )
    name=${parts[${#parts[@]}-1]}
    echo "Flatten > ${name}"
    hardhat flatten "${path}" > "${OUT_DIR}/${name}"
done

echo "Done!"
