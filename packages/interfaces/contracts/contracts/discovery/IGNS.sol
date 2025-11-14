// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6 || ^0.8.0;

/**
 * @title Interface for GNS
 * @author Edge & Node
 * @notice Interface for the Graph Name System (GNS) contract
 */
interface IGNS {
    // -- Pool --

    /**
     * @dev The SubgraphData struct holds information about subgraphs
     * and their signal; both nSignal (i.e. name signal at the GNS level)
     * and vSignal (i.e. version signal at the Curation contract level)
     * @param vSignal The token of the subgraph-deployment bonding curve
     * @param nSignal The token of the subgraph bonding curve
     * @param curatorNSignal Mapping of curator addresses to their name signal amounts
     * @param subgraphDeploymentID The deployment ID this subgraph points to
     * @param __DEPRECATED_reserveRatio Deprecated reserve ratio field
     * @param disabled Whether the subgraph is disabled/deprecated
     * @param withdrawableGRT Amount of GRT available for withdrawal after deprecation
     */
    struct SubgraphData {
        uint256 vSignal; // The token of the subgraph-deployment bonding curve
        uint256 nSignal; // The token of the subgraph bonding curve
        mapping(address => uint256) curatorNSignal;
        bytes32 subgraphDeploymentID;
        uint32 __DEPRECATED_reserveRatio; // solhint-disable-line var-name-mixedcase
        bool disabled;
        uint256 withdrawableGRT;
    }

    /**
     * @dev The LegacySubgraphKey struct holds the account and sequence ID
     * used to generate subgraph IDs in legacy subgraphs.
     * @param account The account that created the legacy subgraph
     * @param accountSeqID The sequence ID for the account's subgraphs
     */
    struct LegacySubgraphKey {
        address account;
        uint256 accountSeqID;
    }

    // -- Configuration --

    /**
     * @notice Approve curation contract to pull funds.
     */
    function approveAll() external;

    /**
     * @notice Set the owner fee percentage. This is used to prevent a subgraph owner to drain all
     * the name curators tokens while upgrading or deprecating and is configurable in parts per million.
     * @param ownerTaxPercentage Owner tax percentage
     */
    function setOwnerTaxPercentage(uint32 ownerTaxPercentage) external;

    // -- Publishing --

    /**
     * @notice Allows a graph account to set a default name
     * @param graphAccount Account that is setting its name
     * @param nameSystem Name system account already has ownership of a name in
     * @param nameIdentifier The unique identifier that is used to identify the name in the system
     * @param name The name being set as default
     */
    function setDefaultName(
        address graphAccount,
        uint8 nameSystem,
        bytes32 nameIdentifier,
        string calldata name
    ) external;

    /**
     * @notice Allows a subgraph owner to update the metadata of a subgraph they have published
     * @param subgraphID Subgraph ID
     * @param subgraphMetadata IPFS hash for the subgraph metadata
     */
    function updateSubgraphMetadata(uint256 subgraphID, bytes32 subgraphMetadata) external;

    /**
     * @notice Publish a new subgraph.
     * @param subgraphDeploymentID Subgraph deployment for the subgraph
     * @param versionMetadata IPFS hash for the subgraph version metadata
     * @param subgraphMetadata IPFS hash for the subgraph metadata
     */
    function publishNewSubgraph(
        bytes32 subgraphDeploymentID,
        bytes32 versionMetadata,
        bytes32 subgraphMetadata
    ) external;

    /**
     * @notice Publish a new version of an existing subgraph.
     * @param subgraphID Subgraph ID
     * @param subgraphDeploymentID Subgraph deployment ID of the new version
     * @param versionMetadata IPFS hash for the subgraph version metadata
     */
    function publishNewVersion(uint256 subgraphID, bytes32 subgraphDeploymentID, bytes32 versionMetadata) external;

    /**
     * @notice Deprecate a subgraph. The bonding curve is destroyed, the vSignal is burned, and the GNS
     * contract holds the GRT from burning the vSignal, which all curators can withdraw manually.
     * Can only be done by the subgraph owner.
     * @param subgraphID Subgraph ID
     */
    function deprecateSubgraph(uint256 subgraphID) external;

    // -- Curation --

    /**
     * @notice Deposit GRT into a subgraph and mint signal.
     * @param subgraphID Subgraph ID
     * @param tokensIn The amount of tokens the nameCurator wants to deposit
     * @param nSignalOutMin Expected minimum amount of name signal to receive
     */
    function mintSignal(uint256 subgraphID, uint256 tokensIn, uint256 nSignalOutMin) external;

    /**
     * @notice Burn signal for a subgraph and return the GRT.
     * @param subgraphID Subgraph ID
     * @param nSignal The amount of nSignal the nameCurator wants to burn
     * @param tokensOutMin Expected minimum amount of tokens to receive
     */
    function burnSignal(uint256 subgraphID, uint256 nSignal, uint256 tokensOutMin) external;

    /**
     * @notice Move subgraph signal from sender to `recipient`
     * @param subgraphID Subgraph ID
     * @param recipient Address to send the signal to
     * @param amount The amount of nSignal to transfer
     */
    function transferSignal(uint256 subgraphID, address recipient, uint256 amount) external;

    /**
     * @notice Withdraw tokens from a deprecated subgraph.
     * When the subgraph is deprecated, any curator can call this function and
     * withdraw the GRT they are entitled for its original deposit
     * @param subgraphID Subgraph ID
     */
    function withdraw(uint256 subgraphID) external;

    // -- Getters --

    /**
     * @notice Return the owner of a subgraph.
     * @param tokenID Subgraph ID
     * @return Owner address
     */
    function ownerOf(uint256 tokenID) external view returns (address);

    /**
     * @notice Return the total signal on the subgraph.
     * @param subgraphID Subgraph ID
     * @return Total signal on the subgraph
     */
    function subgraphSignal(uint256 subgraphID) external view returns (uint256);

    /**
     * @notice Return the total tokens on the subgraph at current value.
     * @param subgraphID Subgraph ID
     * @return Total tokens on the subgraph
     */
    function subgraphTokens(uint256 subgraphID) external view returns (uint256);

    /**
     * @notice Calculate subgraph signal to be returned for an amount of tokens.
     * @param subgraphID Subgraph ID
     * @param tokensIn Tokens being exchanged for subgraph signal
     * @return Amount of subgraph signal that can be bought
     * @return Amount of version signal that can be bought
     * @return Amount of curation tax
     */
    function tokensToNSignal(uint256 subgraphID, uint256 tokensIn) external view returns (uint256, uint256, uint256);

    /**
     * @notice Calculate tokens returned for an amount of subgraph signal.
     * @param subgraphID Subgraph ID
     * @param nSignalIn Subgraph signal being exchanged for tokens
     * @return Amount of tokens returned for an amount of subgraph signal
     * @return Amount of version signal returned
     */
    function nSignalToTokens(uint256 subgraphID, uint256 nSignalIn) external view returns (uint256, uint256);

    /**
     * @notice Calculate subgraph signal to be returned for an amount of subgraph deployment signal.
     * @param subgraphID Subgraph ID
     * @param vSignalIn Amount of subgraph deployment signal to exchange for subgraph signal
     * @return Amount of subgraph signal that can be bought
     */
    function vSignalToNSignal(uint256 subgraphID, uint256 vSignalIn) external view returns (uint256);

    /**
     * @notice Calculate subgraph deployment signal to be returned for an amount of subgraph signal.
     * @param subgraphID Subgraph ID
     * @param nSignalIn Subgraph signal being exchanged for subgraph deployment signal
     * @return Amount of subgraph deployment signal that can be returned
     */
    function nSignalToVSignal(uint256 subgraphID, uint256 nSignalIn) external view returns (uint256);

    /**
     * @notice Get the amount of subgraph signal a curator has.
     * @param subgraphID Subgraph ID
     * @param curator Curator address
     * @return Amount of subgraph signal owned by a curator
     */
    function getCuratorSignal(uint256 subgraphID, address curator) external view returns (uint256);

    /**
     * @notice Return whether a subgraph is published.
     * @param subgraphID Subgraph ID
     * @return Return true if subgraph is currently published
     */
    function isPublished(uint256 subgraphID) external view returns (bool);

    /**
     * @notice Return whether a subgraph is a legacy subgraph (created before subgraph NFTs).
     * @param subgraphID Subgraph ID
     * @return Return true if subgraph is a legacy subgraph
     */
    function isLegacySubgraph(uint256 subgraphID) external view returns (bool);

    /**
     * @notice Returns account and sequence ID for a legacy subgraph (created before subgraph NFTs).
     * @param subgraphID Subgraph ID
     * @return account Account that created the subgraph (or 0 if it's not a legacy subgraph)
     * @return seqID Sequence number for the subgraph
     */
    function getLegacySubgraphKey(uint256 subgraphID) external view returns (address account, uint256 seqID);
}
