pragma solidity ^0.5.2;

import "./Governed.sol";

contract DisputeManager is Governed {
    
    /* 
    * @title Graph Protocol Dispute Resolution Manager contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    *
    * @notice Contract Specification:
    *
    * Dispute resolution is handled through an on-chain dispute resolution process.
    * In the v1 specification the outcome of a dispute will be decided by a centralized 
    * arbitrator (the contract owner / multisig contract) interacting with the on-chain 
    * dispute resolution process.
    * 
    * Requirements ("Dispute Resolution Manager" contract):
    * @req 01 Fishman/disputer can create dispute: In order to be created, disputes require 
    *   a deposit of Graph Tokens equivalent to the amount that may be slashed.
    * @req 02 Slash Stake: In successful dispute, slashingPercent of slashing amount goes 
    *   to Fisherman, the rest goes to Graph DAO (where they are possibly burned).
    * @req 03 Governance can update slashingPercent
    * ...
    */

    /* Events */
    // Dispute was saved by Fisherman/disputor
    event DisputeFiled (bytes _subgraphId, address _fisherman, bytes32 _disputeId);

    /* Structs */
    // Disputes contain info neccessary for the arbitrator to verify and resolve them
    struct dispute {
        bytes readRequest;
        bytes readResponse;
        // bytes indexingNode; // needed?
        // bytes subgraphId; // included in readRequest
        address disputer;
        uint256 depositAmount;
        bool stakeSlashed;
    }

    /* STATE VARIABLES */
    // The disputeManager is solely in control of arbitrating disputes
    address public disputeManager;

    // Disputes created by the Fisherman or other authorized entites
    // @key <bytes> _disputeId - Hash of readIndex data + disputer data
    mapping (bytes32 => dispute) private disputes;

    // Percent of stake to slash in successful dispute
    uint32 public slashingPercent;

    /* Modifiers */
    // Only the designated disputeManager
    modifier onlyDisputeManager;

    /* Contract Constructor */
    constructor () public;

    /* Graph Protocol Functions */
    /**
     * @dev Governance can set the Dispute Manager
     * @param _newDisputeManager <address> Address of the new Dispute Manager
     */
    function setDisputeManager (address _newDisputeManager) public onlyGovernance returns (bool success);

    /**
     * @dev Create a dispute for the disputeManager to resolve
     * @param _readRequest <bytes> JSON RPC data request sent to readIndex
     * @param _readResponse <bytes> JSON RPC data response returned from readIndex
     * @return disputeId <bytes32> ID for the newly created dispute (hash of readIndex data + disputer data)
     * @notice Payable using Graph Tokens for deposit
     */
    function createDispute (bytes memory _readRequest, bytes memory _readResponse) public returns (bytes32 disputeId);

    /**
     * @dev Governance (owner / multisig) can update slashingPercent
     * @param _slashingPercent <uint256> Percent in basis points (parts per 10,000)
     */
    function updateSlashingPercentage (uint256 _slashingPercent) public onlyGovernance returns (bool success);

    /**
     * @dev The disputeManager can verify a dispute as being valid.
     * @param _disputeId <bytes32> ID of the dispute to be verified
     */
    function verifyDispute (bytes32 _disputeId) public onlyDisputeManager returns (bool success);

}