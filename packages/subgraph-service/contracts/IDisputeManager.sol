// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

interface IDisputeManager {
    function getVerifierCut() external view returns (uint256);
    function getDisputePeriod() external view returns (uint64);
}
