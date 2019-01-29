pragma solidity ^0.5.2;

import "./Governed.sol";

contract UpgradableContract is Governed {

    /**
     * @dev Generic upgradable contract for dev purposes
     * @param _governor <address> - Address of the initial `governor` of this contract
     */
    constructor (address _governor) public Governed (_governor) {}

    /**
     * @dev Generic function for dev purposes
     */
    function genericFunction () public onlyGovernance {}

}
