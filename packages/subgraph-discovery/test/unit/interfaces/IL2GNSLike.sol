// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IL2GNSLike {
    event SubgraphMetadataUpdated(uint256 indexed subgraphID, bytes32 subgraphMetadata);
    event SubgraphVersionUpdated(
        uint256 indexed subgraphID,
        bytes32 indexed subgraphDeploymentID,
        bytes32 versionMetadata
    );
    event SignalMinted(
        uint256 indexed subgraphID,
        address indexed curator,
        uint256 nSignalCreated,
        uint256 vSignalCreated,
        uint256 tokensDeposited
    );
    event SignalBurned(
        uint256 indexed subgraphID,
        address indexed curator,
        uint256 nSignalBurnt,
        uint256 vSignalBurnt,
        uint256 tokensReceived
    );
    event SubgraphPublished(uint256 indexed subgraphID, bytes32 indexed subgraphDeploymentID, uint32 reserveRatio);
    event SubgraphUpgraded(
        uint256 indexed subgraphID,
        uint256 vSignalCreated,
        uint256 tokensSignalled,
        bytes32 indexed subgraphDeploymentID
    );
    event SubgraphDeprecated(uint256 indexed subgraphID, uint256 withdrawableGRT);
    event SubgraphReceivedFromL1(
        uint256 indexed _l1SubgraphID,
        uint256 indexed _l2SubgraphID,
        address indexed _owner,
        uint256 _tokens
    );
    event SubgraphL2TransferFinalized(uint256 indexed _l2SubgraphID);
    event CuratorBalanceReceived(
        uint256 indexed _l1SubgraphId,
        uint256 indexed _l2SubgraphID,
        address indexed _l2Curator,
        uint256 _tokens
    );
    event CuratorBalanceReturnedToBeneficiary(
        uint256 indexed _l1SubgraphID,
        address indexed _l2Curator,
        uint256 _tokens
    );

    function initialize(address controller, address subgraphNFT) external;

    function approveAll() external;

    function setCounterpartGNSAddress(address counterpart) external;

    function counterpartGNSAddress() external view returns (address);

    function ownerTaxPercentage() external view returns (uint32);

    function setOwnerTaxPercentage(uint32 ownerTaxPercentage) external;

    function nextAccountSeqID(address account) external view returns (uint256);

    function publishNewSubgraph(
        bytes32 subgraphDeploymentID,
        bytes32 versionMetadata,
        bytes32 subgraphMetadata
    ) external;

    function publishNewVersion(uint256 subgraphID, bytes32 subgraphDeploymentID, bytes32 versionMetadata) external;

    function publishNewVersion(
        uint256 subgraphID,
        bytes32 subgraphDeploymentID,
        bytes32 versionMetadata,
        uint256 signalOutMin
    ) external;

    function deprecateSubgraph(uint256 subgraphID) external;

    function mintSignal(uint256 subgraphID, uint256 tokensIn, uint256 nSignalOutMin) external;

    function burnSignal(uint256 subgraphID, uint256 nSignal, uint256 tokensOutMin) external;

    function onTokenTransfer(address from, uint256 amount, bytes calldata data) external;

    function finishSubgraphTransferFromL1(
        uint256 l2SubgraphID,
        bytes32 subgraphDeploymentID,
        bytes32 subgraphMetadata,
        bytes32 versionMetadata
    ) external;

    function ownerOf(uint256 tokenID) external view returns (address);

    function subgraphs(
        uint256 subgraphID
    )
        external
        view
        returns (
            uint256 vSignal,
            uint256 nSignal,
            bytes32 subgraphDeploymentID,
            uint32 reserveRatio,
            bool disabled,
            uint256 withdrawableGRT
        );

    function subgraphL2TransferData(
        uint256 subgraphID
    ) external view returns (uint256 tokens, bool l2Done, uint256 subgraphReceivedOnL2BlockNumber);

    function getAliasedL2SubgraphID(uint256 l1SubgraphID) external pure returns (uint256);

    function getCuratorSignal(uint256 subgraphID, address curator) external view returns (uint256);

    function tokensToNSignal(uint256 subgraphID, uint256 tokensIn) external view returns (uint256, uint256, uint256);

    function nSignalToTokens(uint256 subgraphID, uint256 nSignalIn) external view returns (uint256, uint256);

    function vSignalToNSignal(uint256 subgraphID, uint256 vSignalIn) external view returns (uint256);
}
