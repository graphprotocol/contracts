// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// Has no onTokenTransfer and no fallback, so any call to it reverts
contract NoCallhookReceiver {}
