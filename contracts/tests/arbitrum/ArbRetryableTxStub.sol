// SPDX-License-Identifier: GPL-2.0-or-later

// This only exists so that our hardhat build gives us an ABI artifact for ArbRetryableTx

pragma solidity ^0.7.6;

import "arbos-precompiles/arbos/builtin/ArbRetryableTx.sol";

abstract contract ArbRetryableTxStub is ArbRetryableTx {}
