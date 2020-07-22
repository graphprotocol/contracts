pragma solidity ^0.6.4;

import "../upgrades/GraphProxyStorage.sol";

contract EpochManagerV1Storage is GraphProxyStorage {
    // -- State --

    // Epoch length in blocks
    uint256 public epochLength;

    // Epoch that was last run
    uint256 public lastRunEpoch;

    // Block and epoch when epoch length was last updated
    uint256 public lastLengthUpdateEpoch;
    uint256 public lastLengthUpdateBlock;
}
