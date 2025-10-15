// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

// solhint-disable named-parameters-mapping
// solhint-disable gas-small-strings

/**
 * @title L1GraphTokenLockTransferToolBadMock
 * @author Edge & Node
 * @notice Mock contract for testing L1 Graph Token Lock Transfer Tool with bad behavior
 */
contract L1GraphTokenLockTransferToolBadMock {
    /**
     * @notice Mapping from L1 wallet address to L2 wallet address
     */
    mapping(address => address) public l2WalletAddress;

    /**
     * @notice Set the L2 wallet address for an L1 wallet
     * @param l1Address L1 wallet address
     * @param l2Address L2 wallet address
     */
    function setL2WalletAddress(address l1Address, address l2Address) external {
        l2WalletAddress[l1Address] = l2Address;
    }

    /**
     * @notice Pull ETH from the contract to the caller (sends 1 wei less than requested for testing)
     * @param l1Wallet L1 wallet address to check
     * @param amount Amount of ETH to pull
     */
    function pullETH(address l1Wallet, uint256 amount) external {
        require(l2WalletAddress[l1Wallet] != address(0), "L1GraphTokenLockTransferToolMock: unknown L1 wallet");
        (bool success, ) = payable(msg.sender).call{ value: amount - 1 }("");
        require(success, "L1GraphTokenLockTransferToolMock: ETH pull failed");
    }
}
