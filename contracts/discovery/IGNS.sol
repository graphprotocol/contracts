// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

interface IGNS {
    // -- Pool --

    struct SubgraphData {
        uint256 vSignal; // The token of the subgraph-deployment bonding curve
        uint256 nSignal; // The token of the subgraph bonding curve
        mapping(address => uint256) curatorNSignal;
        bytes32 subgraphDeploymentID;
        uint32 reserveRatio;
        bool disabled;
        uint256 withdrawableGRT;
    }

    struct LegacySubgraphKey {
        address account;
        uint256 accountSeqID;
    }

    // -- Configuration --

    function approveAll() external;

    function setOwnerTaxPercentage(uint32 _ownerTaxPercentage) external;

    // -- Publishing --

    function setDefaultName(
        address _graphAccount,
        uint8 _nameSystem,
        bytes32 _nameIdentifier,
        string calldata _name
    ) external;

    function updateSubgraphMetadata(uint256 _subgraphID, bytes32 _subgraphMetadata) external;

    function publishNewSubgraph(
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata,
        bytes32 _subgraphMetadata
    ) external;

    function publishNewVersion(
        uint256 _subgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) external;

    function deprecateSubgraph(uint256 _subgraphID) external;

    // -- Curation --

    function mintSignal(
        uint256 _subgraphID,
        uint256 _tokensIn,
        uint256 _nSignalOutMin
    ) external;

    function burnSignal(
        uint256 _subgraphID,
        uint256 _nSignal,
        uint256 _tokensOutMin
    ) external;

    function transferSignal(
        uint256 _subgraphID,
        address _recipient,
        uint256 _amount
    ) external;

    function withdraw(uint256 _subgraphID) external;

    // -- Getters --

    function ownerOf(uint256 _tokenID) external view returns (address);

    function subgraphSignal(uint256 _subgraphID) external view returns (uint256);

    function subgraphTokens(uint256 _subgraphID) external view returns (uint256);

    function tokensToNSignal(uint256 _subgraphID, uint256 _tokensIn)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function nSignalToTokens(uint256 _subgraphID, uint256 _nSignalIn)
        external
        view
        returns (uint256, uint256);

    function vSignalToNSignal(uint256 _subgraphID, uint256 _vSignalIn)
        external
        view
        returns (uint256);

    function nSignalToVSignal(uint256 _subgraphID, uint256 _nSignalIn)
        external
        view
        returns (uint256);

    function getCuratorSignal(uint256 _subgraphID, address _curator)
        external
        view
        returns (uint256);

    function isPublished(uint256 _subgraphID) external view returns (bool);
}
