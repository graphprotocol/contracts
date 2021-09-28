// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../base/Multicall.sol";
import "../bancor/BancorFormula.sol";
import "../upgrades/GraphUpgradeable.sol";
import "../utils/TokenUtils.sol";

import "./IGNS.sol";
import "./GNSStorage.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates subgraph names into subgraph versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 */
contract GNS is GNSV1Storage, GraphUpgradeable, IGNS, Multicall {
    using SafeMath for uint256;

    // -- Constants --

    uint256 private constant MAX_UINT256 = 2**256 - 1;

    // 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;

    // Equates to Connector weight on bancor formula to be CW = 1
    uint32 private constant defaultReserveRatio = 1000000;

    // -- Events --

    /**
     * @dev Emitted when graph account sets its default name
     */
    event SetDefaultName(
        address indexed graphAccount,
        uint256 nameSystem, // only ENS for now
        bytes32 nameIdentifier,
        string name
    );

    /**
     * @dev Emitted when graph account sets a subgraphs metadata on IPFS
     */
    event SubgraphMetadataUpdated(
        address indexed graphAccount,
        uint256 indexed subgraphNumber,
        bytes32 subgraphMetadata
    );

    /**
     * @dev Emitted when a `graph account` publishes a `subgraph` with a `version`.
     * Every time this event is emitted, indicates a new version has been created.
     * The event also emits a `metadataHash` with subgraph details and version details.
     */
    event SubgraphPublished(
        address indexed graphAccount,
        uint256 indexed subgraphNumber,
        bytes32 indexed subgraphDeploymentID,
        bytes32 versionMetadata
    );

    /**
     * @dev Emitted when a graph account deprecated one of its subgraphs
     */
    event SubgraphDeprecated(address indexed graphAccount, uint256 indexed subgraphNumber);

    /**
     * @dev Emitted when a graphAccount creates an nSignal bonding curve that
     * points to a subgraph deployment
     */
    event NameSignalEnabled(
        address indexed graphAccount,
        uint256 indexed subgraphNumber,
        bytes32 indexed subgraphDeploymentID,
        uint32 reserveRatio
    );

    /**
     * @dev Emitted when a name curator deposits its vSignal into an nSignal curve to mint nSignal
     */
    event NSignalMinted(
        address indexed graphAccount,
        uint256 indexed subgraphNumber,
        address indexed nameCurator,
        uint256 nSignalCreated,
        uint256 vSignalCreated,
        uint256 tokensDeposited
    );

    /**
     * @dev Emitted when a name curator burns its nSignal, which in turn burns
     * the vSignal, and receives GRT
     */
    event NSignalBurned(
        address indexed graphAccount,
        uint256 indexed subgraphNumber,
        address indexed nameCurator,
        uint256 nSignalBurnt,
        uint256 vSignalBurnt,
        uint256 tokensReceived
    );

    /**
     * @dev Emitted when a graph account upgrades its nSignal curve to point to a new
     * subgraph deployment, burning all the old vSignal and depositing the GRT into the
     * new vSignal curve, creating new nSignal
     */
    event NameSignalUpgrade(
        address indexed graphAccount,
        uint256 indexed subgraphNumber,
        uint256 newVSignalCreated,
        uint256 tokensSignalled,
        bytes32 indexed subgraphDeploymentID
    );

    /**
     * @dev Emitted when an nSignal curve has been permanently disabled
     */
    event NameSignalDisabled(
        address indexed graphAccount,
        uint256 indexed subgraphNumber,
        uint256 withdrawableGRT
    );

    /**
     * @dev Emitted when a nameCurator withdraws its GRT from a deprecated name signal pool
     */
    event GRTWithdrawn(
        address indexed graphAccount,
        uint256 indexed subgraphNumber,
        address indexed nameCurator,
        uint256 nSignalBurnt,
        uint256 withdrawnGRT
    );

    // -- Modifiers --

    /**
     * @dev Check if the owner is the graph account
     * @param _graphAccount Address of the graph account
     */
    function _isGraphAccountOwner(address _graphAccount) private view {
        address graphAccountOwner = erc1056Registry.identityOwner(_graphAccount);
        require(graphAccountOwner == msg.sender, "GNS: Only graph account owner can call");
    }

    /**
     * @dev Modifier that allows a function to be called by owner of a graph account
     * @param _graphAccount Address of the graph account
     */
    modifier onlyGraphAccountOwner(address _graphAccount) {
        _isGraphAccountOwner(_graphAccount);
        _;
    }

    // -- Functions --

    /**
     * @dev Initialize this contract.
     */
    function initialize(
        address _controller,
        address _bondingCurve,
        address _didRegistry
    ) external onlyImpl {
        Managed._initialize(_controller);

        bondingCurve = _bondingCurve;
        erc1056Registry = IEthereumDIDRegistry(_didRegistry);

        // Settings
        _setOwnerTaxPercentage(500000);
    }

    /**
     * @dev Approve curation contract to pull funds.
     */
    function approveAll() external override {
        graphToken().approve(address(curation()), MAX_UINT256);
    }

    /**
     * @dev Set the owner fee percentage. This is used to prevent a subgraph owner to drain all
     * the name curators tokens while upgrading or deprecating and is configurable in parts per hundred.
     * @param _ownerTaxPercentage Owner tax percentage
     */
    function setOwnerTaxPercentage(uint32 _ownerTaxPercentage) external override onlyGovernor {
        _setOwnerTaxPercentage(_ownerTaxPercentage);
    }

    /**
     * @dev Internal: Set the owner tax percentage. This is used to prevent a subgraph owner to drain all
     * the name curators tokens while upgrading or deprecating and is configurable in parts per hundred.
     * @param _ownerTaxPercentage Owner tax percentage
     */
    function _setOwnerTaxPercentage(uint32 _ownerTaxPercentage) private {
        require(_ownerTaxPercentage <= MAX_PPM, "Owner tax must be MAX_PPM or less");
        ownerTaxPercentage = _ownerTaxPercentage;
        emit ParameterUpdated("ownerTaxPercentage");
    }

    /**
     * @dev Allows a graph account to set a default name
     * @param _graphAccount Account that is setting its name
     * @param _nameSystem Name system account already has ownership of a name in
     * @param _nameIdentifier The unique identifier that is used to identify the name in the system
     * @param _name The name being set as default
     */
    function setDefaultName(
        address _graphAccount,
        uint8 _nameSystem,
        bytes32 _nameIdentifier,
        string calldata _name
    ) external override onlyGraphAccountOwner(_graphAccount) {
        emit SetDefaultName(_graphAccount, _nameSystem, _nameIdentifier, _name);
    }

    /**
     * @dev Allows a graph account update the metadata of a subgraph they have published
     * @param _graphAccount Account that owns the subgraph
     * @param _subgraphNumber Subgraph number
     * @param _subgraphMetadata IPFS hash for the subgraph metadata
     */
    function updateSubgraphMetadata(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _subgraphMetadata
    ) public override onlyGraphAccountOwner(_graphAccount) {
        emit SubgraphMetadataUpdated(_graphAccount, _subgraphNumber, _subgraphMetadata);
    }

    /**
     * @dev Allows a graph account to publish a new subgraph, which means a new subgraph number
     * will be used.
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _versionMetadata IPFS hash for the subgraph version metadata
     * @param _subgraphMetadata IPFS hash for the subgraph metadata
     */
    function publishNewSubgraph(
        address _graphAccount,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata,
        bytes32 _subgraphMetadata
    ) external override notPaused onlyGraphAccountOwner(_graphAccount) {
        uint256 subgraphNumber = graphAccountSubgraphNumbers[_graphAccount];
        _publishVersion(_graphAccount, subgraphNumber, _subgraphDeploymentID, _versionMetadata);
        graphAccountSubgraphNumbers[_graphAccount] = graphAccountSubgraphNumbers[_graphAccount].add(
            1
        );

        curation().setCreatedAt(_subgraphDeploymentID, block.number);

        updateSubgraphMetadata(_graphAccount, subgraphNumber, _subgraphMetadata);
        _enableNameSignal(_graphAccount, subgraphNumber, block.number);
    }

    /**
     * @dev Allows a graph account to publish a new version of its subgraph.
     * Version is derived from the occurrence of SubgraphPublished being emitted.
     * The first time SubgraphPublished is called would be Version 0
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphNumber Subgraph number for the account
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _versionMetadata IPFS hash for the subgraph version metadata
     */
    function publishNewVersion(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) external override notPaused onlyGraphAccountOwner(_graphAccount) {
        require(
            isPublished(_graphAccount, _subgraphNumber),
            "GNS: Cannot update version if not published, or has been deprecated"
        );
        bytes32 oldSubgraphDeploymentID = subgraphs[_graphAccount][_subgraphNumber];
        require(
            _subgraphDeploymentID != oldSubgraphDeploymentID,
            "GNS: Cannot publish a new version with the same subgraph deployment ID"
        );

        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];

        curation().setCreatedAt(_subgraphDeploymentID, namePool.createdAt);

        _publishVersion(_graphAccount, _subgraphNumber, _subgraphDeploymentID, _versionMetadata);
        _upgradeNameSignal(_graphAccount, _subgraphNumber, _subgraphDeploymentID);
    }

    /**
     * @dev Private function used by both external publishing functions
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphNumber Subgraph number for the account
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _versionMetadata IPFS hash for the subgraph version metadata
     */
    function _publishVersion(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) private {
        require(_subgraphDeploymentID != 0, "GNS: Cannot set deploymentID to 0 in publish");

        // Stores a subgraph deployment ID, which indicates a version has been created
        subgraphs[_graphAccount][_subgraphNumber] = _subgraphDeploymentID;

        // Emit version and name data
        emit SubgraphPublished(
            _graphAccount,
            _subgraphNumber,
            _subgraphDeploymentID,
            _versionMetadata
        );
    }

    /**
     * @dev Deprecate a subgraph. Can only be done by the graph account owner.
     * @param _graphAccount Account that is deprecating the subgraph
     * @param _subgraphNumber Subgraph number for the account
     */
    function deprecateSubgraph(address _graphAccount, uint256 _subgraphNumber)
        external
        override
        notPaused
        onlyGraphAccountOwner(_graphAccount)
    {
        require(
            isPublished(_graphAccount, _subgraphNumber),
            "GNS: Cannot deprecate a subgraph which does not exist"
        );

        delete subgraphs[_graphAccount][_subgraphNumber];
        emit SubgraphDeprecated(_graphAccount, _subgraphNumber);

        _disableNameSignal(_graphAccount, _subgraphNumber);
    }

    /**
     * @dev Enable name signal on a graph accounts numbered subgraph, which points to a subgraph
     * deployment
     * @param _graphAccount Graph account enabling name signal
     * @param _subgraphNumber Subgraph number being used
     */
    function _enableNameSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _blockNumber
    ) private {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        namePool.subgraphDeploymentID = subgraphs[_graphAccount][_subgraphNumber];
        namePool.reserveRatio = defaultReserveRatio;
        namePool.createdAt = _blockNumber;

        emit NameSignalEnabled(
            _graphAccount,
            _subgraphNumber,
            namePool.subgraphDeploymentID,
            namePool.reserveRatio
        );
    }

    /**
     * @dev Update a name signal on a graph accounts numbered subgraph
     * @param _graphAccount Graph account updating name signal
     * @param _subgraphNumber Subgraph number being used
     * @param _newSubgraphDeploymentID Deployment ID being upgraded to
     */
    function _upgradeNameSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _newSubgraphDeploymentID
    ) private {
        // This is to prevent the owner from front running its name curators signal by posting
        // its own signal ahead, bringing the name curators in, and dumping on them
        ICuration curation = curation();
        require(
            !curation.isCurated(_newSubgraphDeploymentID),
            "GNS: Owner cannot point to a subgraphID that has been pre-curated"
        );

        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(
            namePool.nSignal > 0,
            "GNS: There must be nSignal on this subgraph for curve math to work"
        );
        require(namePool.disabled == false, "GNS: Cannot be disabled");

        // Burn all version signal in the name pool for tokens
        uint256 tokens = curation.burn(namePool.subgraphDeploymentID, namePool.vSignal, 0);

        // Take the owner cut of the curation tax, add it to the total
        uint32 curationTaxPercentage = curation.curationTaxPercentage();
        uint256 tokensWithTax = _chargeOwnerTax(tokens, _graphAccount, curationTaxPercentage);

        // Update pool: constant nSignal, vSignal can change
        namePool.subgraphDeploymentID = _newSubgraphDeploymentID;
        (namePool.vSignal, ) = curation.mint(namePool.subgraphDeploymentID, tokensWithTax, 0);

        emit NameSignalUpgrade(
            _graphAccount,
            _subgraphNumber,
            namePool.vSignal,
            tokensWithTax,
            _newSubgraphDeploymentID
        );
    }

    /**
     * @dev Allow a name curator to mint some nSignal by depositing GRT
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number
     * @param _tokensIn The amount of tokens the nameCurator wants to deposit
     * @param _nSignalOutMin Expected minimum amount of name signal to receive
     */
    function mintNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _tokensIn,
        uint256 _nSignalOutMin
    ) external override notPartialPaused {
        // Pool checks
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(namePool.disabled == false, "GNS: Cannot be disabled");
        require(
            namePool.subgraphDeploymentID != 0,
            "GNS: Must deposit on a name signal that exists"
        );

        // Pull tokens from sender
        TokenUtils.pullTokens(graphToken(), msg.sender, _tokensIn);

        // Get name signal to mint for tokens deposited
        (uint256 vSignal, ) = curation().mint(namePool.subgraphDeploymentID, _tokensIn, 0);
        uint256 nSignal = vSignalToNSignal(_graphAccount, _subgraphNumber, vSignal);

        // Slippage protection
        require(nSignal >= _nSignalOutMin, "GNS: Slippage protection");

        // Update pools
        namePool.vSignal = namePool.vSignal.add(vSignal);
        namePool.nSignal = namePool.nSignal.add(nSignal);
        namePool.curatorNSignal[msg.sender] = namePool.curatorNSignal[msg.sender].add(nSignal);

        emit NSignalMinted(_graphAccount, _subgraphNumber, msg.sender, nSignal, vSignal, _tokensIn);
    }

    /**
     * @dev Allow a nameCurator to burn some of its nSignal and get GRT in return
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _nSignal The amount of nSignal the nameCurator wants to burn
     * @param _tokensOutMin Expected minimum amount of tokens to receive
     */
    function burnNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignal,
        uint256 _tokensOutMin
    ) external override notPartialPaused {
        // Pool checks
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(namePool.disabled == false, "GNS: Cannot be disabled");

        // Curator balance checks
        uint256 curatorNSignal = namePool.curatorNSignal[msg.sender];
        require(
            _nSignal <= curatorNSignal,
            "GNS: Curator cannot withdraw more nSignal than they have"
        );

        // Get tokens for name signal amount to burn
        uint256 vSignal = nSignalToVSignal(_graphAccount, _subgraphNumber, _nSignal);
        uint256 tokens = curation().burn(namePool.subgraphDeploymentID, vSignal, _tokensOutMin);

        // Update pools
        namePool.vSignal = namePool.vSignal.sub(vSignal);
        namePool.nSignal = namePool.nSignal.sub(_nSignal);
        namePool.curatorNSignal[msg.sender] = namePool.curatorNSignal[msg.sender].sub(_nSignal);

        // Return the tokens to the curator
        TokenUtils.pushTokens(graphToken(), msg.sender, tokens);

        emit NSignalBurned(_graphAccount, _subgraphNumber, msg.sender, _nSignal, vSignal, tokens);
    }

    /**
     * @dev Owner disables the subgraph. This means the subgraph-number combination can no longer
     * be used for name signal. The nSignal curve is destroyed, the vSignal is burned, and the GNS
     * contract holds the GRT from burning the vSignal, which all curators can withdraw manually.
     * @param _graphAccount Account that is deprecating its name curation
     * @param _subgraphNumber Subgraph number
     */
    function _disableNameSignal(address _graphAccount, uint256 _subgraphNumber) private {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];

        // If no nSignal, then no need to burn vSignal
        if (namePool.nSignal != 0) {
            // Note: No slippage, burn at any cost
            namePool.withdrawableGRT = curation().burn(
                namePool.subgraphDeploymentID,
                namePool.vSignal,
                0
            );
            namePool.vSignal = 0;
        }

        // Set the NameCurationPool fields to make it disabled
        namePool.disabled = true;

        emit NameSignalDisabled(_graphAccount, _subgraphNumber, namePool.withdrawableGRT);
    }

    /**
     * @dev When the subgraph curve is disabled, all nameCurators can call this function and
     * withdraw the GRT they are entitled for its original deposit of vSignal
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     */
    function withdraw(address _graphAccount, uint256 _subgraphNumber)
        external
        override
        notPartialPaused
    {
        // Pool checks
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(namePool.disabled == true, "GNS: Name bonding curve must be disabled first");
        require(namePool.withdrawableGRT > 0, "GNS: No more GRT to withdraw");

        // Curator balance checks
        uint256 curatorNSignal = namePool.curatorNSignal[msg.sender];
        require(curatorNSignal > 0, "GNS: Curator must have some nSignal to withdraw GRT");

        // Get curator share of tokens to be withdrawn
        uint256 tokensOut = curatorNSignal.mul(namePool.withdrawableGRT).div(namePool.nSignal);
        namePool.curatorNSignal[msg.sender] = 0;
        namePool.nSignal = namePool.nSignal.sub(curatorNSignal);
        namePool.withdrawableGRT = namePool.withdrawableGRT.sub(tokensOut);

        // Return tokens to the curator
        TokenUtils.pushTokens(graphToken(), msg.sender, tokensOut);

        emit GRTWithdrawn(_graphAccount, _subgraphNumber, msg.sender, curatorNSignal, tokensOut);
    }

    /**
     * @dev Calculate tax that owner will have to cover for upgrading or deprecating.
     * @param _tokens Tokens that were received from deprecating the old subgraph
     * @param _owner Subgraph owner
     * @param _curationTaxPercentage Tax percentage on curation deposits from Curation contract
     * @return Total tokens that will be sent to curation, _tokens + ownerTax
     */
    function _chargeOwnerTax(
        uint256 _tokens,
        address _owner,
        uint32 _curationTaxPercentage
    ) private returns (uint256) {
        if (_curationTaxPercentage == 0 || ownerTaxPercentage == 0) {
            return 0;
        }

        // Tax on the total bonding curve funds
        uint256 taxOnOriginal = _tokens.mul(_curationTaxPercentage).div(MAX_PPM);
        // Total after the tax
        uint256 totalWithoutOwnerTax = _tokens.sub(taxOnOriginal);
        // The portion of tax that the owner will pay
        uint256 ownerTax = taxOnOriginal.mul(ownerTaxPercentage).div(MAX_PPM);

        uint256 totalWithOwnerTax = totalWithoutOwnerTax.add(ownerTax);

        // The total after tax, plus owner partial repay, divided by
        // the tax, to adjust it slightly upwards. ex:
        // 100 GRT, 5 GRT Tax, owner pays 100% --> 5 GRT
        // To get 100 in the protocol after tax, Owner deposits
        // ~5.26, as ~105.26 * .95 = 100
        uint256 totalAdjustedUp = totalWithOwnerTax.mul(MAX_PPM).div(
            uint256(MAX_PPM).sub(uint256(_curationTaxPercentage))
        );

        uint256 ownerTaxAdjustedUp = totalAdjustedUp.sub(_tokens);

        // Get the owner of the subgraph to reimburse the curation tax
        TokenUtils.pullTokens(graphToken(), _owner, ownerTaxAdjustedUp);

        return totalAdjustedUp;
    }

    /**
     * @dev Calculate name signal to be returned for an amount of tokens.
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _tokensIn Tokens being exchanged for name signal
     * @return Amount of name signal and curation tax
     */
    function tokensToNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _tokensIn
    )
        public
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        (uint256 vSignal, uint256 curationTax) = curation().tokensToSignal(
            namePool.subgraphDeploymentID,
            _tokensIn
        );
        uint256 nSignal = vSignalToNSignal(_graphAccount, _subgraphNumber, vSignal);
        return (vSignal, nSignal, curationTax);
    }

    /**
     * @dev Calculate tokens returned for an amount of name signal.
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _nSignalIn Name signal being exchanged for tokens
     * @return Amount of tokens returned for an amount of nSignal
     */
    function nSignalToTokens(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignalIn
    ) public view override returns (uint256, uint256) {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = nSignalToVSignal(_graphAccount, _subgraphNumber, _nSignalIn);
        uint256 tokensOut = curation().signalToTokens(namePool.subgraphDeploymentID, vSignal);
        return (vSignal, tokensOut);
    }

    /**
     * @dev Calculate nSignal to be returned for an amount of vSignal.
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _vSignalIn Amount of vSignal to exchange for name signal
     * @return Amount of nSignal that can be bought
     */
    function vSignalToNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _vSignalIn
    ) public view override returns (uint256) {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];

        // Handle initialization by using 1:1 version to name signal
        if (namePool.vSignal == 0) {
            return _vSignalIn;
        }

        return
            BancorFormula(bondingCurve).calculatePurchaseReturn(
                namePool.nSignal,
                namePool.vSignal,
                namePool.reserveRatio,
                _vSignalIn
            );
    }

    /**
     * @dev Calculate vSignal to be returned for an amount of name signal.
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _nSignalIn Name signal being exchanged for vSignal
     * @return Amount of vSignal that can be returned
     */
    function nSignalToVSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignalIn
    ) public view override returns (uint256) {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        return
            BancorFormula(bondingCurve).calculateSaleReturn(
                namePool.nSignal,
                namePool.vSignal,
                namePool.reserveRatio,
                _nSignalIn
            );
    }

    /**
     * @dev Get the amount of name signal a curator has on a name pool.
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _curator Curator to look up to see n signal balance
     * @return Amount of name signal owned by a curator for the name pool
     */
    function getCuratorNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        address _curator
    ) public view override returns (uint256) {
        return nameSignals[_graphAccount][_subgraphNumber].curatorNSignal[_curator];
    }

    /**
     * @dev Return whether a subgraph name is published.
     * @param _graphAccount Account being checked
     * @param _subgraphNumber Subgraph number being checked for publishing
     * @return Return true if subgraph is currently published
     */
    function isPublished(address _graphAccount, uint256 _subgraphNumber)
        public
        view
        override
        returns (bool)
    {
        return subgraphs[_graphAccount][_subgraphNumber] != 0;
    }
}
