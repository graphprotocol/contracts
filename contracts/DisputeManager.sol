pragma solidity ^0.5.2;

/*
 * @title Dispute Resolution Manager contract
 *
 * @author Bryant Eisenbach
 * @author Reuven Etzion
 *
 * Requirements
 * @req 01 Slash Stake: In successful dispute, slashingPercent of slashing amount goes
 *         to Fisherman, the rest goes to Graph DAO (where they are possibly burned).
 * @req 02 Governance can update slashingPercent
 *
 * @notice Dispute resolution is handled through an on-chain dispute resolution
 *         process. In the v1 specification the outcome of a dispute will be decided
 *         by a centralized arbitrator (the contract owner / multisig contract)
 *         interacting with the on-chain dispute resolution process.
 */

import "./Governed.sol";

contract DisputeManager is Governed {

    /* Events */
    // Dispute was saved by Fisherman/disputor
    event DisputeFiled (bytes _subgraphId, address _fisherman, bytes32 _disputeId);

    /* Structs */
    // Store 34 byte IPFS hash as 32 bytes
    struct IpfsHash {
        bytes32 ipfsHash;
        uint8 ipfsHashFunction;
    }

    // Disputes contain info neccessary for the arbitrator to verify and resolve them
    struct Dispute {
        IpfsHash ipfsHash;
        bytes readRequest;
        bytes readResponse;
        // bytes indexingNode; // needed?
        // bytes subgraphId; // included in readRequest
        address disputer;
        uint256 depositAmount;
        bool stakeSlashed;
    }

    /* STATE VARIABLES */
    // The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;

    // Disputes created by the Fisherman or other authorized entites
    // @key <bytes32> _disputeId - Hash of readIndex data + disputer data
    mapping (bytes32 => Dispute) private disputes;

    /* Modifiers */
    // Only the designated arbitrator
    modifier onlyArbitrator () {
        require(msg.sender == arbitrator);
        _;
    }

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed(_governor) {}

    /* Graph Protocol Functions */
    /**
     * @dev Governance can set the Arbitrator
     * @param _newArbitrator <address> Address of the new Arbitrator
     */
    function setArbitrator (address _newArbitrator) public onlyGovernance returns (bool success)
    {
        revert();
    }

    /**
     * @dev Create a dispute for the arbitrator to resolve
     * @param _readRequest <bytes> JSON RPC data request sent to readIndex
     * @param _readResponse <bytes> JSON RPC data response returned from readIndex
     * @return disputeId <bytes32> ID for the newly created dispute (hash of readIndex data + disputer data)
     * @notice Payable using Graph Tokens for deposit
     */
    function createDispute (bytes memory _readRequest, bytes memory _readResponse) public returns (bytes32 disputeId)
    {
        revert();
    }

    /**
     * @dev The arbitrator can verify a dispute as being valid.
     * @param _disputeId <bytes32> ID of the dispute to be verified
     */
    function verifyDispute (bytes32 _disputeId) public onlyArbitrator returns (bool success)
    {
        revert();
    }

}
