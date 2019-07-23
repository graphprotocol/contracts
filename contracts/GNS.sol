pragma solidity ^0.5.2;

import "./Governed.sol";

contract GNS is Governed{

    /*
    * @title Graph Name Service (GNS) contract
    *
    * @author Bryant Eisenbach
    * @author Reuven Etzion
    * @author Ashoka Finley
    * @notice Contract Specification:
    *
    * Subgraph IDs : Subgraph definitions are immutable, even though the actual
    * data ingested may grow -- each subgraph manifest is hashed in its IPLD
    * canonical serialized form, to produce a unique Id. Nodes in the peer-to-peer
    * network use this Id to communicate who is indexing and caching what data, as
    * well as route queries through the network. The self-certifying nature of
    * subgraph IDs also make them useful for providing attestations and filing disputes.
    *
    * Domains : Subgraph IDs can also be associated with a domain name in the Graph
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
    * The Subgraph IDs are emitted in events. Only the owners can emit this events
    * This means Subgraph IDs are not stored in this contract anywhere
    * Therefore, subgraph IDs are mapped to domain names only through events (see requirements below).
    *
    * Requirements ("GNS" contract):
    * req 01 Maps domains to owners.
    * req 02 Emit events that connect domain names to subgraph IDs.
    * req 03 Emit events that connect subdomain names to subgraph ID.
    * ...
    */

    /* Events */
    event DomainAdded(bytes32 indexed topLevelDomainHash, address indexed owner, string domainName);
    event DomainTransferred(bytes32 indexed topLevelDomainHash, address indexed newOwner);
    event SubgraphIDAdded(
        bytes32 indexed topLevelDomainHash,
        bytes32 indexed subdomainHash,
        bytes32 indexed subgraphID,
        string subdomainName,
        bytes32 ipfsHash
    );
    event SubgraphIDChanged(
        bytes32 indexed topLevelDomainHash,
        bytes32 indexed subdomainHash,
        bytes32 indexed subgraphID
    );
    event SubgraphIDDeleted(bytes32 indexed topLevelDomainHash, bytes32 indexed subdomainHash);

    event AccountMetadataChanged(address indexed account, bytes32 indexed ipfsHash);
    event SubgraphMetadataChanged(bytes32 indexed topLevelDomainHash, bytes32 indexed subdomainHash, bytes32 indexed ipfsHash);

    /* STATE VARIABLES */
    // Storage of a hashed top level domain to owners.
    mapping(bytes32 => address) public domainOwners;

    // Storage of a hashed top level domain mapped to an a subdomain that maps to a boolean.
    // If a top-level domain and subdomain map to true, this means the subdomain is registered.
    mapping(bytes32 => mapping(bytes32 => bool)) public subdomains;

    // Top level domain or subdomain hash to subgraph ID.
    mapping(bytes32 => bytes32) public domainsToSubgraphIDs;

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed(_governor) {}

    /* Graph Protocol Functions */

    modifier onlyDomainOwner (bytes32 _topLevelDomainHash) {
        require(msg.sender == domainOwners[_topLevelDomainHash], "Only domain owner can call");
        _;
    }

    /*
     * @notice Register a domain to an owner.
     *
     * @param _domainName <string> - Domain name, which is treated as a username.
     */
    function registerDomain(string calldata _domainName) external {
        // Require that this domain is not yet owned by anyone.
        require(domainOwners[keccak256(abi.encodePacked(_domainName))] == address(0), 'Domain is already owned.');

        domainOwners[keccak256(abi.encodePacked(_domainName))] = msg.sender;
        emit DomainAdded(keccak256(abi.encodePacked(_domainName)), msg.sender, _domainName);
    }

    /*
     * @notice Register a subgraph ID to a subdomain. Only works when the subgraph has not been registered yet. After this, updates can be made via changeDomainSubgraphID
     * @notice To only register to the top level domain, pass _subdomainName as the top level domain.
     * @dev Only the domain owner may do this.
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name.
     * @param _subdomainName <string> - Name of the Subdomain - the full name, such as "david.thegraph.com".
     * @param _subgraphID <bytes32> - IPLD subgraph ID of the subdomain.
     */
    function addSubgraphToDomain(
        bytes32 _topLevelDomainHash,
        string calldata _subdomainName,
        bytes32 _subgraphID,
        bytes32 _ipfsHash
    ) external onlyDomainOwner(_topLevelDomainHash) {
        bytes32 domainHash = keccak256(abi.encodePacked(_subdomainName));
        require(domainsToSubgraphIDs[domainHash] == bytes32(0), 'The domain must already be registered in order to add a subgraph ID.');

        // Domain has never been registered, we need to add it to the mapping.
        subdomains[_topLevelDomainHash][domainHash] = true;

        // Store the subgraph ID to the domain hash.
        domainsToSubgraphIDs[domainHash] = _subgraphID;

        // subdomainName and ipfsHash are only emitted through the event.
        emit SubgraphIDAdded(_topLevelDomainHash, domainHash, _subgraphID, _subdomainName, _ipfsHash);
    }

    /*
     * @notice Update an existing subdomain with a different subgraph ID.
     * @dev Only the domain owner may do this.
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name.
     * @param _subdomainHash <bytes32> - Hash of the Name of the subdomain.
     * @param _subgraphID <bytes32> - IPLD subgraph ID of the subdomain.
     */
    function changeDomainSubgraphID(
        bytes32 _topLevelDomainHash,
        bytes32 _subdomainHash,
        bytes32 _subgraphID
    ) external onlyDomainOwner(_topLevelDomainHash) {

        require(domainsToSubgraphIDs[_subdomainHash] != bytes32(0), 'The domain must already be registered in order to change its subgraph ID.');
        domainsToSubgraphIDs[_subdomainHash] = _subgraphID;

        emit SubgraphIDChanged(_topLevelDomainHash, _subdomainHash, _subgraphID);
    }

    /*
     * @notice Remove an existing subdomain from the provided subdomainName.
     * @dev Only the domain owner may do this.
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name.
     * @param _subdomainHash <bytes32> - Hash of the name of the subdomain.
     */
    function deleteSubdomain(bytes32 _topLevelDomainHash, bytes32 _subdomainHash) external onlyDomainOwner(_topLevelDomainHash) {
        require(domainsToSubgraphIDs[_subdomainHash] != bytes32(0));
        delete domainsToSubgraphIDs[_subdomainHash];
        delete subdomains[_topLevelDomainHash][_subdomainHash];
        emit SubgraphIDDeleted(_topLevelDomainHash, _subdomainHash);
    }

    /*
     * @notice Transfer ownership of domain by existing domain owner.
     * @dev Only the domain owner may do this.
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the domain name.
     * @param _newOwner <address> - New owner of the domain.
     */
    function transferDomainOwnership(bytes32 _topLevelDomainHash, address _newOwner) external onlyDomainOwner(_topLevelDomainHash) {
        domainOwners[_topLevelDomainHash] = _newOwner;
        emit DomainTransferred(_topLevelDomainHash, _newOwner);
    }

    /*
     * @notice Change or initalize the Account Metadata, which is stored in a schema on IPFS.
     * @dev Only the msg.sender can do this.
     *
     * @param _ipfsHash <bytes32> - Hash of the IPFS file that stores the account metadata.
     * @param _account <address> - msg.sender.
     */
    function changeAccountMetadata(bytes32 _ipfsHash) external {
        emit AccountMetadataChanged(msg.sender, _ipfsHash);
    }

    /*
    * @notice Change or initalize the Account Metadata, which is stored in a schema on IPFS.
    * @dev Only the msg.sender can do this.
    *
    * @param _ipfsHash <bytes32> - Hash of the IPFS file that stores the subgraph metadata.
    * @param _topLevelDomainHash <bytes32> - Hash of the domain name.
    * @param _subdomainHash <bytes32> - Hash of the name of the subdomain.
    */
    function changeSubgraphMetadata(bytes32 _ipfsHash, bytes32 _topLevelDomainHash, bytes32 _subdomainHash) external onlyDomainOwner(_topLevelDomainHash) {
        emit SubgraphMetadataChanged(_topLevelDomainHash, _subdomainHash, _ipfsHash);
    }

}
