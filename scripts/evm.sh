#!/usr/bin/env bash

# Exit script as soon as a command fails.
set -o errexit

MNEMONIC="myth like bonus scare over problem client lizard pioneer submit female collect"
TESTRPC_PORT=8545

testrpc_running() {
  nc -z localhost "$TESTRPC_PORT"
}

start_testrpc() {
  npx ganache-cli -m "$MNEMONIC" -i 15 --gasLimit 8000000 --port "$TESTRPC_PORT" > /dev/null &
  testrpc_pid=$!
}

# Run testrpc if needed
if [ -z "$SOLIDITY_COVERAGE" ]; then
  if testrpc_running; then
    echo "Killing testrpc instance at port $TESTRPC_PORT"
    kill -9 $(lsof -i:$TESTRPC_PORT -t)
  fi

  echo "Starting our own testrpc instance at port $TESTRPC_PORT"
  start_testrpc
  sleep 5
fi

# Exit error mode so the testrpc instance always gets killed
set +e
result=0

if [ "$SOLIDITY_COVERAGE" = true ]; then
  # Solidity-coverage runs its own testrpc
  npx buidler coverage --network localhost "$@"
  result=$?
else
  # Run tests using testrpc started in this script
  npx buidler test --network localhost "$@"
  result=$?
fi

kill -9 $testrpc_pid

exit $result
