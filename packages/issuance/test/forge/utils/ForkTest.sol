// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.30;

import "./BaseTest.sol";
import "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import "./mocks/MockRewardsManager.sol";
import "./mocks/MockGraphProxy.sol";

/**
 * @title ForkTest
 * @notice Base contract for fork tests
 */
abstract contract ForkTest is BaseTest {
    // Network configuration
    uint256 internal forkId;

    // Common contract addresses
    address internal graphTokenAddress;
    address internal controllerAddress;
    address internal governorAddress;
    address internal rewardsManagerAddress;

    // Contract interfaces
    IGraphToken internal graphToken;

    /**
     * @notice Set up fork test
     * @param _rpcUrl RPC URL to fork from
     * @param _blockNumber Block number to fork from (0 for latest)
     */
    function setUpFork(string memory _rpcUrl, uint256 _blockNumber) internal {
        if (_blockNumber > 0) {
            forkId = vm.createFork(_rpcUrl, _blockNumber);
        } else {
            forkId = vm.createFork(_rpcUrl);
        }
        vm.selectFork(forkId);

        // Set up contract addresses based on the network
        _setupContractAddresses();

        // Set up contract interfaces
        graphToken = IGraphToken(graphTokenAddress);

        // Override the governor with the actual governor address
        governor = governorAddress;

        // Label known addresses
        vm.label(graphTokenAddress, "GraphToken");
        vm.label(controllerAddress, "Controller");
        vm.label(governorAddress, "Governor");
        vm.label(rewardsManagerAddress, "RewardsManager");
    }

    /**
     * @notice Set up contract addresses based on the network
     * This should be overridden by specific network fork tests
     */
    function _setupContractAddresses() internal virtual;

    /**
     * @notice Impersonate an account
     * @param _account Address to impersonate
     */
    function impersonateAccount(address _account) internal {
        vm.startPrank(_account);
    }

    /**
     * @notice Stop impersonating an account
     */
    function stopImpersonatingAccount() internal {
        vm.stopPrank();
    }

    /**
     * @notice Get the current governor of a governed contract
     * @param _governed Address of the governed contract
     * @return Address of the governor
     */
    function getGovernor(address _governed) internal view returns (address) {
        // Call the governor() function directly using a low-level call
        // This avoids having to import the Governed contract
        (bool success, bytes memory data) = _governed.staticcall(abi.encodeWithSignature("governor()"));
        require(success, "Failed to get governor");
        return abi.decode(data, (address));
    }
}
