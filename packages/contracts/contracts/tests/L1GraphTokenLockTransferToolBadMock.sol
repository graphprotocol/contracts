// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

contract L1GraphTokenLockTransferToolBadMock {
    mapping(address => address) public l2WalletAddress;

    function setL2WalletAddress(address _l1Address, address _l2Address) external {
        l2WalletAddress[_l1Address] = _l2Address;
    }

    // Sends 1 wei less than requested
    function pullETH(address _l1Wallet, uint256 _amount) external {
        require(
            l2WalletAddress[_l1Wallet] != address(0),
            "L1GraphTokenLockTransferToolMock: unknown L1 wallet"
        );
        (bool success, ) = payable(msg.sender).call{ value: _amount - 1 }("");
        require(success, "L1GraphTokenLockTransferToolMock: ETH pull failed");
    }
}
