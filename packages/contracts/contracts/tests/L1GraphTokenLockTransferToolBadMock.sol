// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable gas-small-strings, use-natspec

contract L1GraphTokenLockTransferToolBadMock {
    /**
     * @notice Mapping from L1 wallet address to L2 wallet address
     */
    mapping(address => address) public l2WalletAddress;

    /**
     * @notice Set the L2 wallet address for an L1 wallet
     * @param _l1Address L1 wallet address
     * @param _l2Address L2 wallet address
     */
    function setL2WalletAddress(address _l1Address, address _l2Address) external {
        l2WalletAddress[_l1Address] = _l2Address;
    }

    /**
     * @notice Pull ETH from the contract to the caller (sends 1 wei less than requested for testing)
     * @param _l1Wallet L1 wallet address to check
     * @param _amount Amount of ETH to pull
     */
    function pullETH(address _l1Wallet, uint256 _amount) external {
        require(l2WalletAddress[_l1Wallet] != address(0), "L1GraphTokenLockTransferToolMock: unknown L1 wallet");
        (bool success, ) = payable(msg.sender).call{ value: _amount - 1 }("");
        require(success, "L1GraphTokenLockTransferToolMock: ETH pull failed");
    }
}
