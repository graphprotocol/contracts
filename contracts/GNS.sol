pragma solidity ^0.5.2;

import "./Governed.sol";

contract GNS is Governed {

    /*
    * @title Graph Name Service (GNS) contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    * @author Ashoka Finley
    * @notice Contract Specification:
    *
    * Subgraph Ids : Subgraph definitions are immutable, even though the actual
    * data ingested may grow -- each subgraph manifest is hashed in its IPLD
    * canonical serialized form, to produce a unique Id. Nodes in the peer-to-peer
    * network use this Id to communicate who is indexing and caching what data, as
    * well as route queries through the network. The self-certifying nature of
    * subgraph Ids also make them useful for providing attestations and filing disputes.
    *
    * Domains : Subgraph Ids can also be associated with a domain name in the Graph
    * Name Service (GNS) to provide a mutable reference to a subgraph. This can be
    * useful for writing more human readable queries, always querying the latest version
    * of a subgraph, specifying relationships between subgraphs or mutably referencing a
    * subgraph in smart contracts.
    *
    * Deploying a subgraph to a domain also enables discoverability, as explorer UIs will
    * be built on top of the GNS.
    *
    * Subdomains : An owner of a domain in the GNS may wish to deploy multiple subgraphs
    * to a single domain, and have them exist in separate namespaces. Sub-domains enable
    * this use case, and add an optional additional layer of namespacing beyond that
    * already provided by the top level domains.
    *
    * See: https://github.com/graphprotocol/specs/tree/master/data-model for details.
    *
    * The SubgraphIds are emitted in events. Only the owners can emit this events
    * This means SubgraphIds are not stored in this contract anywhere
    * Therefore, subgraphIds are mapped to domain names only through events (see requirements below)
    *
    * Requirements ("GNS" contract):
    * req 01 Maps domains to owners
    * req 02 Emit events that connect domain names to subgraphIds
    * req 03 Emit events that connect subdomain names to subgraphId
    * ...
    */

    /* Events */
    event DomainAdded(bytes32 indexed topLevelDomainHash, address indexed owner, string domainName);
    event DomainTransferred(bytes32 indexed topLevelDomainHash, address indexed newOwner);
    event SubgraphIdAdded(
        bytes32 indexed topLevelDomainHash,
        bytes32 indexed subdomainHash,
        bytes32 indexed subgraphId,
        string subdomainName,
        bytes32 ipfsHash
    );
    event SubgraphIdChanged(
        bytes32 indexed topLevelDomainHash,
        bytes32 indexed subdomainHash,
        bytes32 indexed subgraphId
    );
    event SubgraphIdDeleted(bytes32 indexed topLevelDomainHash, bytes32 indexed subdomainHash);

    event AccountMetadataChanged(address indexed account, bytes32 indexed ipfsHash);
    event SubgraphMetadataChanged(bytes32 indexed topLevelDomainHash, bytes32 indexed subdomainHash, bytes32 indexed ipfsHash);

    /* Structs */
    struct Domain {
        address owner;
    }

    /* STATE VARIABLES */
    // Storage of a Hashed Domain Name mapped to its owner
    mapping (bytes32 => Domain) internal gnsDomains;

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed (_governor) {}

    /* Graph Protocol Functions */

    modifier onlyDomainOwner (bytes32 _topLevelDomainHash) {
        require(msg.sender == gnsDomains[_topLevelDomainHash].owner);
        _;
    }

    /*
     * @notice Register a Domain to an owner
     * @dev Only registrar may do this
     *
     * @param _domainName <string> - Domain name
     * @param _owner <address> - Address of domain owner
     */
    function registerDomain (string calldata _domainName, address _owner) external onlyGovernance {
        gnsDomains[keccak256(abi.encodePacked(_domainName))] = Domain({owner: _owner});
        emit DomainAdded(keccak256(abi.encodePacked(_domainName)), _owner, _domainName);  // 3rd field will automatically be hashed by EVM
    }

    /*
     * @notice Get the owner of an existing domain
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name
     */
    function getDomainOwner (bytes32 _topLevelDomainHash) external view returns (address owner) {
        return gnsDomains[_topLevelDomainHash].owner;
    }

    /*
     * @notice Register a subgraphId to a subdomain
     * @notice To only register to the top level domain, pass _subdomainName as a blank string (which is c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 when hashed)
     * @dev Only the domain owner may do this
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name
     * @param _subdomainName <string> - Name of the Subdomain
     * @param _subgraphId <bytes32> - IPLD SubgraphId of the subdomain
     */
    function addSubgraphToDomain (
        bytes32 _topLevelDomainHash,
        string calldata _subdomainName,
        bytes32 _subgraphId,
        bytes32 _ipfsHash
    ) external onlyDomainOwner(_topLevelDomainHash) {
        emit SubgraphIdAdded(_topLevelDomainHash, keccak256(abi.encodePacked(_subdomainName)), _subgraphId, _subdomainName, _ipfsHash);
    }

    /*
     * @notice Update an existing subdomain with a different subgraphId
     * @dev Only the domain owner may do this
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name
     * @param _subdomainHash <bytes32> - Hash of the Name of the subdomain
     * @param _subgraphId <bytes32> - IPLD SubgraphId of the subdomain
     */
    function changeDomainSubgraphId (
        bytes32 _topLevelDomainHash,
        bytes32 _subdomainHash,
        bytes32 _subgraphId
    ) external onlyDomainOwner(_topLevelDomainHash) {
        emit SubgraphIdChanged(_topLevelDomainHash, _subdomainHash, _subgraphId);
    }

    /*
     * @notice Remove an existing subdomain from the provided subdomainName
     * @dev Only the domain owner may do this
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name
     * @param _subdomainHash <bytes32> - Hash of the name of the subdomain
     */
    function deleteSubdomain (bytes32 _topLevelDomainHash, bytes32 _subdomainHash) external onlyDomainOwner(_topLevelDomainHash) {
        emit SubgraphIdDeleted(_topLevelDomainHash, _subdomainHash);
    }

    /*
     * @notice Transfer ownership of domain by existing domain owner
     * @dev Only the domain owner may do this
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name
     * @param _newOwner <address> - New owner of the domain
     */
    function transferDomainOwnership (bytes32 _topLevelDomainHash, address _newOwner) external onlyDomainOwner(_topLevelDomainHash) {
        gnsDomains[_topLevelDomainHash].owner = _newOwner;
        emit DomainTransferred(_topLevelDomainHash, _newOwner);
    }

    /*
     * @notice Change or initalize the Account Metadata, which is stored in a schema on IPFS
     * @dev Only the msg.sender can do this
     *
     * @param _ipfsHash <bytes32> - Hash of the IPFS file that stores the account metadata
     * @param _account <address> - msg.sender
     */
    function changeAccountMetadata (bytes32 _ipfsHash) external {
        emit AccountMetadataChanged(msg.sender, _ipfsHash);
    }

    /*
    * @notice Change or initalize the Account Metadata, which is stored in a schema on IPFS
    * @dev Only the msg.sender can do this
    *
    * @param _ipfsHash <bytes32> - Hash of the IPFS file that stores the subgraph metadata
    * @param _topLevelDomainHash <bytes32> - Hash of the domain name
    * @param _subdomainHash <bytes32> - Hash of the name of the subdomain
    */
    function changeSubgraphMetadata (bytes32 _ipfsHash, bytes32 _topLevelDomainHash, bytes32 _subdomainHash) external onlyDomainOwner(_topLevelDomainHash) {
        emit SubgraphMetadataChanged(_topLevelDomainHash, _subdomainHash, _ipfsHash);
    }

}
