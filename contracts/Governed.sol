pragma solidity ^0.5.2;

contract Governed {
    address public governor;

    event GovernanceTransferred(address indexed _from, address indexed _to);

    constructor() public;

    modifier onlyGovernance;

    function transferGovernance(address _newOwner) public onlyOwner;

}