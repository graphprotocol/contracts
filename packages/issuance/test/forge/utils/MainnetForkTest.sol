// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import "./ForkTest.sol";

/**
 * @title MainnetForkTest
 * @notice Base contract for mainnet fork tests
 */
abstract contract MainnetForkTest is ForkTest {
    /**
     * @notice Set up mainnet fork test
     * @param _blockNumber Block number to fork from (0 for latest)
     */
    function setUpMainnetFork(uint256 _blockNumber) internal {
        string memory mainnetRpcUrl = vm.envString("MAINNET_RPC_URL");
        setUpFork(mainnetRpcUrl, _blockNumber);
    }

    /**
     * @notice Set up contract addresses for mainnet
     */
    function _setupContractAddresses() internal override {
        // Mainnet contract addresses
        graphTokenAddress = 0xc944E90C64B2c07662A292be6244BDf05Cda44a7;
        controllerAddress = 0x0AeE8703D34DD9aE107386d3eFF22AE75Dd616D1;
        rewardsManagerAddress = 0x9Ac758AB77733b4150A901ebd659cbF8cB93ED66;
    }
}
