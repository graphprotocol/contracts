pragma solidity ^0.6.4;

contract Governed {
    /*
     * @title Graph Contract Governance contract
     *
     * @author Bryant Eisenbach
     * @author Reuven Etzion
     *
     * @notice Contract Specification:
     *
     * There are several parameters throughout this mechanism design which are set via a
     * governance process. In the v1 specification, governance will consist of a small committee
     * which enacts changes to the protocol via a multi-sig contract.
     *
     * Requirements ("Governed" contract):
     * req 01 Multisig contract will own this contract
     * req 02 Verify the Governed contracts can upgrade themselves to a new `governor`
     *   (GovA owns contracts 1-5 and can transfer ownership of 1-5 to GovB)
     * ...
     * Version 2
     * req 01 (V2) Change Mutli-sig to use a voting mechanism
     *   - Majority of votes after N% of votes cast will trigger proposed actions
     */

    address public governor;

    event GovernanceTransferred(address indexed _from, address indexed _to);

    /**
     * @dev All `Governed` contracts are constructed using an address for the `governor`
     * @param _governor <address> Address of initial `governor` of the contract
     */
    constructor(address _governor) public {
        governor = _governor;
    }

    modifier onlyGovernance {
        require(msg.sender == governor, "Only Governor can call");
        _;
    }

    /**
     * @dev The current `governor` can assign a new `governor`
     * @param _newGovernor <address> Address of new `governor`
     */
    function transferGovernance(address _newGovernor)
        public
        onlyGovernance
        returns (bool)
    {
        governor = _newGovernor;
        return true;
    }
}
