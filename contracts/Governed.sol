pragma solidity ^0.5.2;

contract Governed {
    address public executor;

    event GovernanceTransferred(address indexed _from, address indexed _to);

    constructor() public;

    modifier onlyExecutor;

    function transferGovernance(address _newOwner) public onlyExecutor;

}