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
    * canonical serialized form, to produce a unique ID. Nodes in the peer-to-peer
    * network use this ID to communicate who is indexing and caching what data, as
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
    * Requirements ("GNS" contract):
    * req 01 Maps owners to domains
    * req 02 Maps domain names to subgraphIDs
    * req 03 Maps subdomain names to domains of subgraphIDs
    * req 04 Event to emit human-readable names
    * ...
    */

    /* Events */
    event domainAdded(string indexed domainName, bytes32 indexed domainHash, address indexed owner);
    event subdomainAdded(
        bytes32 indexed domainHash,
        bytes32 indexed subdomainHash,
        bytes32 indexed subdomainSubgraphID,
        string subdomainName
    );
    event subdomainUpdated(
        bytes32 indexed domainHash,
        bytes32 indexed subdomainHash,
        bytes32 indexed subdomainSubgraphID
    );
    event subdomainDeleted(bytes32 indexed domainHash, bytes32 indexed subdomainHash);

    /* Structs */
    struct Domain {
        address owner;
    }

    // The subgraph ID is the manifest which is hashed, these IDs are unique
    // Domains which are also hashed are attached to subgraphIDs
    /* STATE VARIABLES */
    // Storage of Domain Names mapped to subgraphID's
    mapping (bytes32 => Domain) internal gnsDomains;

    /* Contract Constructor */
    /* @param _governor <address> - Address of the multisig contract as Governor of this contract */
    constructor (address _governor) public Governed (_governor) {}

    /* Graph Protocol Functions */

    modifier onlyDomainOwner (bytes32 _domainHash) {
        require(msg.sender == gnsDomains[_domainHash].owner);
        _;
    }
    /*
     * @notice Add a subgraphID and register owner
     * @dev Only registrar may do this
     *
     * @param _domainName <string> - Domain name
     * @param _owner <address> - Address of domain owner
     * @param _subgraphID <bytes32> - IPLD Hash of the subgraph manifest
     */
    function registerDomain (string calldata _domainName, address _owner) external onlyGovernance {
        gnsDomains[keccak256(abi.encodePacked(_domainName))] = Domain({owner: _owner});
        emit domainAdded(_domainName, keccak256(abi.encodePacked(_domainName)), _owner);
    }

    /*
     * @notice Get the owner of an existing domain
     * @param _domainHash <bytes32> - Hash of the domain name
     * @return owner <address> - Owner of the domain
     * @return subgraphID <bytes32> - ID of the subgraph
     */
    function getDomainOwner (bytes32 _domainHash) external returns (address owner) {
        return gnsDomains[_domainHash].owner;
    }

    /*
     * @notice Add a subdomain to the provided subgraphID
     * @dev Only the domain owner may do this
     *
     * @param _domainHash <bytes32> - Hash of the domain name
     * @param _subdomainName <string> - Name of the Subdomain
     * @param _subdomainSubgraphID <bytes32> - IPLD SubgraphID of the subdomain
     */
    function addSubdomain (
        bytes32 _domainHash,
        string calldata _subdomainName,
        bytes32 _subdomainSubgraphID
    ) external onlyDomainOwner(_domainHash) {
        emit subdomainAdded(_domainHash, _subdomainName, keccak256(abi.encodePacked(_subdomainName)), _subdomainSubgraphID);
    }


    /*
     * @notice Update an existing subdomain with a new subgraphID
     * @dev Only the domain owner may do this
     *
     * @param _domainHash <bytes32> - Hash of the domain name
     * @param _subdomainHash <bytes32> - Hash of the Name of the subdomain
     * @param _subdomainSubgraphID <bytes32> - IPLD SubgraphID of the subdomain
     */
    function updateSubdomain (
        bytes32 _domainHash,
        bytes32 _subdomainHash,
        bytes32 _subdomainSubgraphID
    ) external onlyDomainOwner(_domainHash) {
        emit subdomainUpdated(_domainHash, _subdomainHash, _subdomainSubgraphID);
    }

    /*
     * @notice Remove an existing subdomain from the provided subdomainName
     * @dev Only the domain owner may do this
     *
     * @param _domainHash <bytes32> - Hash of the domain name
     * @param _subdomainHash <bytes32> - Hash of the name of the subdomain
     */
    function deleteSubdomain (bytes32 _domainHash, bytes32 _subdomainHash) external onlyDomainOwner(_domainHash) {
        emit subdomainDeleted(_domainHash, _subdomainHash);
    }

    /*
     * @notice Get the subgraphID of an existing subdomain for a given domain
     * @param _domainHash <bytes32> - Hash of the domain name
     * @param _subdomainHash <bytes32> - Name of the subdomain
     * @return subdomainSubgraphID <bytes32> - IPLD SubgraphID of the subdomain
     */
     function getSubdomainSubgraphID (
        bytes32 _domainHash,
        bytes32 _subdomainHash
     ) external returns (bytes32 subdomainSubgraphID) {
        return gnsDomains[_domainHash].subdomainsToSubgraphIDs[_subdomainHash];
     }

    /*
     * @notice Transfer ownership of domain by existing domain owner
     * @dev Only the domain owner may do this
     *
     * @param _domainHash <bytes32> - Hash of the domain name
     * @param _newOwner <address> - New owner of the domain
     */
    function transferDomainOwnership (bytes32 _domainHash, address _newOwner) external onlyDomainOwner(_domainHash) {
        gnsDomains[_domainHash].owner = _newOwner;
        emit domainTransferred(_domainHash, _newOwner);
    }
}
