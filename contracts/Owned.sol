pragma solidity ^0.5.2;

// ----------------------------------------------------------------------------
// Owned contract from The Ethereum Wiki - ERC20 Token Standard
// https://theethereum.wiki/w/index.php/ERC20_Token_Standard
// ----------------------------------------------------------------------------
contract Owned {
    address public owner;
    address public newOwner;

    event OwnershipTransferPending(address indexed _to);
    event OwnershipTransferredAccepted(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        newOwner = _newOwner;
        emit OwnershipTransferPending(newOwner);
    }
    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferredAccepted(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}