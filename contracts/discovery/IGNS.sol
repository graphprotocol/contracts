pragma solidity ^0.6.12;

interface IGNS {
    // -- Pool --

    struct NameCurationPool {
        uint256 vSignal; // The token of the subgraph deployment bonding curve
        uint256 nSignal; // The token of the name curation bonding curve
        mapping(address => uint256) curatorNSignal;
        bytes32 subgraphDeploymentID;
        uint32 reserveRatio;
        bool disabled;
        uint256 withdrawableGRT;
    }

    // -- Configuration --

    function approveAll() external;

    function setMinimumVsignal(uint256 _minimumVSignalStake) external;

    function setOwnerFeePercentage(uint32 _ownerFeePercentage) external;

    // -- Publishing --

    function setDefaultName(
        address _graphAccount,
        uint8 _nameSystem,
        bytes32 _nameIdentifier,
        string calldata _name
    ) external;

    function updateSubgraphMetadata(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _subgraphMetadata
    ) external;

    function publishNewSubgraph(
        address _graphAccount,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata,
        bytes32 _subgraphMetadata
    ) external;

    function publishNewVersion(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) external;

    function deprecateSubgraph(address _graphAccount, uint256 _subgraphNumber) external;

    // -- Curation --

    function mintNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _tokens
    ) external;

    function burnNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignal
    ) external;

    function withdraw(address _graphAccount, uint256 _subgraphNumber) external;

    // -- Getters --

    function tokensToNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _tokens
    ) external view returns (uint256, uint256);

    function nSignalToTokens(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignal
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function vSignalToNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _vSignal
    ) external view returns (uint256);

    function nSignalToVSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignal
    ) external view returns (uint256);

    function getCuratorNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        address _curator
    ) external view returns (uint256);

    function isPublished(address _graphAccount, uint256 _subgraphNumber)
        external
        view
        returns (bool);
}
