pragma solidity ^0.5.2;

import "./Owned.sol";

contract Governed is Owned {

    modifier onlyGovernance;

}