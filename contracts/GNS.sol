pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./Governed.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized namings system for subgraphs
 * used in the scope of the Graph Network. It translate subgraph names into
 * subgraphDeploymentID regarded as versions.
 */
contract GNS is Governed {
    // -- Types --

    enum RecordType { GNS }

    struct Record {
        address owner;
        bytes32 subgraphDeploymentID;
        RecordType nameSystem;
    }

    // -- State --

    mapping(bytes32 => Record) public records;

    // -- Events --

    /**
     * @dev Emitted when `owner` publish a `subgraphDeploymentID` version under subgraph `name`.
     * The event also attach `metadataHash` with extra information.
     */
    event SubgraphPublished(
        string name,
        address owner,
        bytes32 subgraphDeploymentID,
        bytes32 metadataHash
    );

    /**
     * @dev Emitted when subgraph `nameHash` is unpublished by its owner.
     */
    event SubgraphUnpublished(bytes32 nameHash);

    /**
     * @dev Emitted when subgraph `nameHash` is transferred to new owner.
     */
    event SubgraphTransferred(bytes32 nameHash, address from, address to);

    modifier onlyRecordOwner(bytes32 _nameHash) {
        require(msg.sender == records[_nameHash].owner, "GNS: Only record owner can call");
        _;
    }

    /**
     * @dev Contract Constructor.
     * @param _governor Owner address of this contract
     */
    constructor(address _governor) public Governed(_governor) {}

    /**
     * @dev Publish a version using `subgraphDeploymentID` under a subgraph..
     * @param _name Name of the subgraph
     * @param _subgraphDeploymentID SubgraphDeployment to link to the subgraph
     * @param _metadataHash IPFS hash linked to the metadata
     */
    function publish(
        string calldata _name,
        bytes32 _subgraphDeploymentID,
        bytes32 _metadataHash
    ) external {
        address owner = msg.sender;
        bytes32 nameHash = keccak256(bytes(_name));
        require(
            !isReserved(nameHash) || records[nameHash].owner == owner,
            "GNS: Record reserved, only record owner can publish"
        );

        records[nameHash] = Record(owner, _subgraphDeploymentID, RecordType.GNS);
        emit SubgraphPublished(_name, owner, _subgraphDeploymentID, _metadataHash);
    }

    /**
     * @dev Unpublish a subgraph name. Can only be done by the owner.
     * @param _nameHash Keccak256 hash of the subgraph name
     */
    function unpublish(bytes32 _nameHash) external onlyRecordOwner(_nameHash) {
        delete records[_nameHash];
        emit SubgraphUnpublished(_nameHash);
    }

    /**
     * @dev Tranfer the subgraph name to a new owner.
     * @param _nameHash Keccak256 hash of the subgraph name
     * @param _to Address of the new owner
     */
    function transfer(bytes32 _nameHash, address _to) external onlyRecordOwner(_nameHash) {
        require(_to != address(0), "GNS: Cannot transfer to empty address");
        require(records[_nameHash].owner != _to, "GNS: Cannot transfer to itself");
        records[_nameHash].owner = _to;
        emit SubgraphTransferred(_nameHash, msg.sender, _to);
    }

    /**
     * @dev Return whether a subgraph name is registed or not.
     * @param _nameHash Keccak256 hash of the subgraph name
     * @return Return true if subgraph name exists
     */
    function isReserved(bytes32 _nameHash) public view returns (bool) {
        return records[_nameHash].owner != address(0);
    }
}
