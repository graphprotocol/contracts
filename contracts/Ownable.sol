pragma solidity ^0.5.2;

// ----------------------------------------------------------------------------
// Owned contract from The Ethereum Wiki - ERC20 Token Standard
// https://theethereum.wiki/w/index.php/ERC20_Token_Standard
// ----------------------------------------------------------------------------
contract Owned {
    address public owner;
    address public newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public;

    modifier onlyOwner;

    function transferOwnership(address _newOwner) public onlyOwner;
    function acceptOwnership() public;
}