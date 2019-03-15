pragma solidity ^0.5.2;

/*
 * @title Dispute Resolution Manager contract
 *
 * @author Bryant Eisenbach
 * @author Reuven Etzion
 *
 * Fisherman Requirements
 * @req f01 A fisherman can provide a bond, a valid read request and an invalid read
 *          response which has been signed by a current indexing node to create a
 *          dispute.
 * @req f02 If the dispute is validated by arbitration, the fisherman should receive a
 *          reward proportional to the amount staked by the indexing node.
 *
 * Dispute Arbitrator Requirements
 * @req a01 The arbitrator can rule to accept a proposed dispute, which will trigger a
 *          slashing of the indexing node that the dispute concerns.
 * @req a02 The arbitrator can rule to reject a proposed dispute, which will slash the
 *          bond posted by the fisherman who proposed it.
 *
 * @notice Dispute resolution is handled through an on-chain dispute resolution
 *         process. In the v1 specification the outcome of a dispute will be decided
 *         by a centralized arbitrator (the contract owner / multisig contract)
 *         interacting with the on-chain dispute resolution process.
 */

import "./Governed.sol";
import "./Staking.sol";
import "./GraphToken.sol";

contract DisputeManager is Governed
{
    /* Events */
    // @dev Dispute was saved by Fisherman/disputor
    event DisputeFiled (bytes _subgraphId, address _fisherman, bytes32 _disputeId);

    /* Structs */
    // @dev Store 34 byte IPFS hash as 32 bytes
    struct IpfsHash {
        bytes32 ipfsHash;
        uint8 ipfsHashFunction;
    }

    // @dev Disputes contain info neccessary for the arbitrator to verify and resolve
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
    // @dev The arbitrator is solely in control of arbitrating disputes
    address public arbitrator;
    // @dev Staking contract address (set only at runtime)
    Staking staking;

    // @dev Graph Token address
    GraphToken token;

    // @dev Disputes created by the Fisherman or other authorized entites
    // @key <bytes32> _disputeId - Hash of readIndex data + disputer data
    mapping (bytes32 => Dispute) private disputes;

    /* Modifiers */
    // Only the designated arbitrator has access (Governance in v1 of Graph Protocol)
    modifier onlyArbitrator () {
        require(msg.sender == governor);
        _;
    }

    /**
     * @param _staking <address> - Address of the staking contract
     * @param _token <address> - Address of the Graph Token contract
     * @param _governor <address> - Address of the multisig contract as Governor of
     *                              this contract
     */
    constructor (
        address _staking,
        address _token,
        address _governor
    )
        public
        Governed(_governor)
    {
        staking = Staking(_staking);
        token = GraphToken(_token);
    }

    /**
     * @dev Create a dispute for the arbitrator to resolve
     * @param _readRequest <bytes> - JSON RPC data request sent to readIndex
     * @param _readResponse <bytes> - JSON RPC data response returned from readIndex
     * @return disputeId <bytes32> - ID for the newly created dispute
     *                               (hash of readIndex data + disputer data)
     * @notice Payable using Graph Tokens for deposit
     */
    function createDispute (
        bytes memory _readRequest,
        bytes memory _readResponse
    )
        public
        returns (bytes32 disputeId)
    {
        revert();
    }

    /**
     * @dev The arbitrator can verify a dispute as being valid.
     * @param _disputeId <bytes32> - ID of the dispute to be verified
     */
    function verifyDispute (
        bytes32 _disputeId
    )
        public
        onlyArbitrator
        returns (bool success)
    {
        revert();
    }
}
