pragma solidity ^0.5.2;

import "./Owned.sol";

contract DisputeManager is Owned {
    
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
    * @req 03 Owner/multisig can update slashingPercent
    * ...
    */

    /* Events */
    // Dispute was saved by Fisherman/disputor
    event DisputeFiled (bytes _subgraphId, address _fisherman, bytes _disputeId);

    /* STATE VARIABLES */
    // Disputes created by the Fisherman or other authorized entites
    // @key <bytes> _disputeId - Hash of readIndex data + disputer data
    mapping (bytes => dispute) private disputes;

    // Percent of stake to slash in successful dispute
    uint32 public slashingPercent;

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

    /* Contract Constructor */
    constructor () public;

    /* Graph Protocol Functions */
    /**
     * @dev Create a dispute for the arbitrator (owner / multisig) to resolve
     * @param _readRequest <bytes> JSON RPC data request sent to readIndex
     * @param _readResponse <bytes> JSON RPC data response returned from readIndex
     * @return disputeId <bytes> ID for the newly created dispute (hash of readIndex data + disputer data)
     * @notice Payable using Graph Tokens for deposit
     */
    function createDispute (bytes memory _readRequest, bytes memory _readResponse) public returns (bytes disputeId) {}

    /**
     * @dev Arbitrator (owner / multisig) can slash staked Graph Tokens in dispute
     * @param _disputeId <bytes> Hash of readIndex data + disputer data
     */
    function slashStake (bytes memory _disputeId) public onlyOwner returns (bool success);

    /**
     * @dev Governance (owner / multisig) can update slashingPercent
     * @param _slashingPercent <uint128> Percent in basis points (parts per 10,000)
     */
    function updateSlashingPercentage (uint128 _slashingPercent) public onlyOwner returns (bool success);

}