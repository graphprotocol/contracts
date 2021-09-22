#!/bin/bash

set -eo pipefail

MNEMONIC="myth like bonus scare over problem client lizard pioneer submit female collect"
TESTRPC_PORT=8545

### Functions

evm_running() {
  nc -z localhost "$TESTRPC_PORT"
}

evm_start() {
  echo "Starting our own evm instance at port $TESTRPC_PORT"
  npx hardhat node --port "$TESTRPC_PORT" > /dev/null &
}

evm_kill() {
  if evm_running; then
    echo "Killing evm instance at port $TESTRPC_PORT"
    kill -9 $(lsof -i:$TESTRPC_PORT -t)
  fi
}

### Setup EVM

# Ensure we compiled sources

yarn build

# Gas reporter needs to run in its own evm instance
if [ "$RUN_EVM" = true  ]; then
  evm_kill
  evm_start
  sleep 5
fi

### Main

mkdir -p reports

# Run using the standalone evm instance
npx hardhat test --network hardhat

### Cleanup

# Exit error mode so the evm instance always gets killed
set +e
result=0

if [ "$RUN_EVM" = true ]; then
  evm_kill
fi

exit $result
