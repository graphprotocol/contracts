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
        bytes32 indexed domainHash,
        bytes32 indexed subgraphID
    );
    event DomainDeleted(bytes32 indexed domainHash);

    event AccountMetadataChanged(address indexed account, bytes32 indexed ipfsHash);
    event SubgraphMetadataChanged(bytes32 indexed domainHash, bytes32 indexed ipfsHash);

    /* TYPES */
    struct Domain {
        address owner;
        bytes32 subgraphID;
    }

    /* STATE VARIABLES */
    // Storage of a hashed top level domain to owners.
    mapping(bytes32 => Domain) public domains; // TODO - this is the only owner

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed(_governor) {}

    /* Graph Protocol Functions */

    modifier onlyDomainOwner (bytes32 _domainHash) {
        require(msg.sender == domains[_domainHash].owner, "Only domain owner can call");
        _;
    }

    /*
     * @notice Register a domain to an owner.
     *
     * @param _domainName <string> - Domain name, which is treated as a username.
     */
    function registerDomain(string calldata _domainName) external {
        // Require that this domain is not yet owned by anyone.
        require(domains[keccak256(abi.encodePacked(_domainName))].owner == address(0), 'Domain is already owned.');

        domains[keccak256(abi.encodePacked(_domainName))].owner = msg.sender;
        emit DomainAdded(keccak256(abi.encodePacked(_domainName)), msg.sender, _domainName);
    }

    /*
     * @notice Register a subgraph ID to a subdomain. Only works when the subgraph has not been registered yet. After this, updates can be made via changeDomainSubgraphID
     * @notice To only register to the top level domain, pass _subdomainName as a blank string
     * @dev Only the domain owner may do this.
     *
     * @param _topLevelDomainHash <bytes32> - Hash of the top level domain name.
     * @param _subdomainName <string> - Name of the Subdomain - the full name, such as "david.thegraph.com".
     * @param _subgraphID <bytes32> - IPLD subgraph ID of the subdomain.
     */
    function addSubgraphToDomain(
        bytes32 _topLevelDomainHash,
        string calldata _subdomainName,
        bytes32 _subgraphID,
        bytes32 _ipfsHash
    ) external onlyDomainOwner(_topLevelDomainHash) {
        bytes32 domainHash;
        bytes32 subdomainHash = keccak256(abi.encodePacked(_subdomainName));

        // Subdomain is blank, therefore we are setting the subgraphID of the top level domain
        if (subdomainHash == keccak256("")) {
            // The domain hash ends up being the top level domain hash.
            domainHash = _topLevelDomainHash;
        } else {
            // The domain hash becomes the hash the subdomain concatenated with the top level domain hash.
            domainHash = keccak256(abi.encodePacked(subdomainHash, _topLevelDomainHash));
            require(domains[domainHash].owner == msg.sender, 'You must be the owner of the subdomain. You may have lost ownership if you transferred it away.');
        }
        require(domains[domainHash].subgraphID == bytes32(0), 'The subgraph ID for this domain has already been set. You must call changeDomainSubgraphID it you wish to change it.');
        domains[domainHash].subgraphID = _subgraphID;

        // subdomainName and ipfsHash are only emitted through the event.
        // Note - if the subdomain is blank, the domain hash ends up being the top level domain hash, not the hash of a blank string.
        emit SubgraphIDAdded(_topLevelDomainHash, domainHash, _subgraphID, _subdomainName, _ipfsHash);
    }

    /*
     * @notice Update an existing subdomain with a different subgraph ID.
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     * @param _subgraphID <bytes32> - IPLD subgraph ID of the domain.
     */
    function changeDomainSubgraphID(
        bytes32 _domainHash,
        bytes32 _subgraphID
    ) external onlyDomainOwner(_domainHash) {
        require(domains[_domainHash].subgraphID != bytes32(0), 'The subgraph ID must have been set at least once in order to change it.');
        domains[_domainHash].subgraphID = _subgraphID;

        emit SubgraphIDChanged(_domainHash, _subgraphID);
    }

    /*
     * @notice Remove an existing domain owner and subgraphID
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     */
    function deleteSubdomain(bytes32 _domainHash) external onlyDomainOwner(_domainHash) {
        delete domains[_domainHash];
        emit DomainDeleted(_domainHash);
    }

    /*
     * @notice Transfer ownership of domain by existing domain owner.
     * @dev Only the domain owner may do this.
     *
     * @param _domainHash <bytes32> - Hash of the domain name.
     * @param _newOwner <address> - New owner of the domain.
     */
    function transferDomainOwnership(bytes32 _domainHash, address _newOwner) external onlyDomainOwner(_domainHash) {
        domains[_domainHash].owner = _newOwner;
        emit DomainTransferred(_domainHash, _newOwner);
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
    * @param _domainHash <bytes32> - Hash of the domain name.
    */
    function changeSubgraphMetadata(bytes32 _ipfsHash, bytes32 _domainHash) external onlyDomainOwner(_domainHash) {
        emit SubgraphMetadataChanged(_domainHash, _ipfsHash);
    }

}
