// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import "./ForkTest.sol";

/**
 * @title ArbitrumForkTest
 * @notice Base contract for Arbitrum fork tests
 */
abstract contract ArbitrumForkTest is ForkTest {
    /**
     * @notice Set up Arbitrum fork test
     * @param _blockNumber Block number to fork from (0 for latest)
     */
    function setUpArbitrumFork(uint256 _blockNumber) internal {
        string memory arbitrumRpcUrl = vm.envString("ARBITRUM_RPC_URL");
        setUpFork(arbitrumRpcUrl, _blockNumber);
    }

    /**
     * @notice Set up contract addresses for Arbitrum
     */
    function _setupContractAddresses() internal override {
        // Arbitrum contract addresses
        graphTokenAddress = 0x9623063377AD1B27544C965cCd7342f7EA7e88C7; // L2GraphToken on Arbitrum
        controllerAddress = 0x0a8491544221dd212964fbb96487467291b2C97e; // Controller on Arbitrum
        governorAddress = 0x8C6de8F8D562f3382417340A6994601eE08D3809; // L2GraphToken Governor on Arbitrum

        // Note: If the RewardsManager doesn't exist at this address, we'll need to deploy it
        rewardsManagerAddress = 0x971B9d3d0Ae3ECa029CAB5eA1fB0F72c85e6a525; // RewardsManager on Arbitrum
    }
}
