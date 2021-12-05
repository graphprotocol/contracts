// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../base/Multicall.sol";
import "../base/SubgraphNFT.sol";
import "../bancor/BancorFormula.sol";
import "../upgrades/GraphUpgradeable.sol";
import "../utils/TokenUtils.sol";

import "./IGNS.sol";
import "./GNSStorage.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 */
contract GNS is GNSV2Storage, GraphUpgradeable, IGNS, Multicall {
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
     * @dev Emitted when the subgraph metadata is updated.
     */
    event SubgraphMetadataUpdated(uint256 indexed subgraphID, bytes32 subgraphMetadata);

    /**
     * @dev Emitted when a subgraph version is updated.
     */
    event SubgraphVersionUpdated(
        uint256 indexed subgraphID,
        bytes32 indexed subgraphDeploymentID,
        bytes32 versionMetadata
    );

    /**
     * @dev Emitted when a curator mints signal.
     */
    event SignalMinted(
        uint256 indexed subgraphID,
        address indexed curator,
        uint256 nSignalCreated,
        uint256 vSignalCreated,
        uint256 tokensDeposited
    );

    /**
     * @dev Emitted when a curator burns signal.
     */
    event SignalBurned(
        uint256 indexed subgraphID,
        address indexed curator,
        uint256 nSignalBurnt,
        uint256 vSignalBurnt,
        uint256 tokensReceived
    );

    /**
     * @dev Emitted when a subgraph is created.
     */
    event SubgraphPublished(
        uint256 indexed subgraphID,
        bytes32 indexed subgraphDeploymentID,
        uint32 reserveRatio
    );

    /**
     * @dev Emitted when a subgraph is upgraded to point to a new
     * subgraph deployment, burning all the old vSignal and depositing the GRT into the
     * new vSignal curve.
     */
    event SubgraphUpgraded(
        uint256 indexed subgraphID,
        uint256 vSignalCreated,
        uint256 tokensSignalled,
        bytes32 indexed subgraphDeploymentID
    );

    /**
     * @dev Emitted when a subgraph upgrade is finalized
     */
    event SubgraphUpgradeFinalized(
        uint256 indexed subgraphID,
        bytes32 indexed subgraphDeploymentID,
        uint256 vSignal
    );

    /**
     * @dev Emitted when a subgraph is deprecated.
     */
    event SubgraphDeprecated(uint256 indexed subgraphID, uint256 withdrawableGRT);

    /**
     * @dev Emitted when a curator withdraws GRT from a deprecated subgraph
     */
    event GRTWithdrawn(
        uint256 indexed subgraphID,
        address indexed curator,
        uint256 nSignalBurnt,
        uint256 withdrawnGRT
    );

    // -- Modifiers --

    /**
     * @dev Emitted when a legacy subgraph is claimed
     */
    event LegacySubgraphClaimed(address indexed graphAccount, uint256 subgraphNumber);

    /**
     * @dev Modifier that allows only a subgraph operator to be the caller
     */
    modifier onlySubgraphAuth(uint256 _subgraphID) {
        require(ownerOf(_subgraphID) == msg.sender, "GNS: Must be authorized");
        _;
    }

    // -- Functions --

    /**
     * @dev Initialize this contract.
     */
    function initialize(
        address _controller,
        address _bondingCurve,
        address _tokenDescriptor
    ) external onlyImpl {
        Managed._initialize(_controller);

        // Dependencies
        bondingCurve = _bondingCurve;
        __SubgraphNFT_init(_tokenDescriptor);

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
     * the name curators tokens while upgrading or deprecating and is configurable in parts per million.
     * @param _ownerTaxPercentage Owner tax percentage
     */
    function setOwnerTaxPercentage(uint32 _ownerTaxPercentage) external override onlyGovernor {
        _setOwnerTaxPercentage(_ownerTaxPercentage);
    }

    /**
     * @dev Set the token descriptor contract.
     * @param _tokenDescriptor Address of the contract that creates the NFT token URI
     */
    function setTokenDescriptor(address _tokenDescriptor) external override onlyGovernor {
        _setTokenDescriptor(_tokenDescriptor);
    }

    /**
     * @dev Internal: Set the owner tax percentage. This is used to prevent a subgraph owner to drain all
     * the name curators tokens while upgrading or deprecating and is configurable in parts per million.
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
    ) external override {
        require(_graphAccount == msg.sender, "GNS: Only you can set your name");
        emit SetDefaultName(_graphAccount, _nameSystem, _nameIdentifier, _name);
    }

    /**
     * @dev Allows a subgraph owner to update the metadata of a subgraph they have published
     * @param _subgraphID Subgraph ID
     * @param _subgraphMetadata IPFS hash for the subgraph metadata
     */
    function updateSubgraphMetadata(uint256 _subgraphID, bytes32 _subgraphMetadata)
        public
        override
        onlySubgraphAuth(_subgraphID)
    {
        emit SubgraphMetadataUpdated(_subgraphID, _subgraphMetadata);
    }

    /**
     * @dev Publish a new subgraph.
     * @param _subgraphDeploymentID Subgraph deployment for the subgraph
     * @param _versionMetadata IPFS hash for the subgraph version metadata
     * @param _subgraphMetadata IPFS hash for the subgraph metadata
     */
    function publishNewSubgraph(
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata,
        bytes32 _subgraphMetadata
    ) external override notPaused {
        // Subgraph deployment must be non-empty
        require(_subgraphDeploymentID != 0, "GNS: Cannot set deploymentID to 0 in publish");

        // Init the subgraph
        address subgraphOwner = msg.sender;
        uint256 subgraphID = _nextSubgraphID(subgraphOwner);
        SubgraphData storage subgraphData = _getSubgraphData(subgraphID);
        subgraphData.subgraphDeploymentID = _subgraphDeploymentID;
        subgraphData.reserveRatio = defaultReserveRatio;

        // Init version
        subgraphData.versions[VersionType.Current].subgraphDeploymentID = _subgraphDeploymentID;

        // Mint the NFT. Use the subgraphID as tokenId.
        // This function will check the if tokenId already exists.
        _mint(subgraphOwner, subgraphID);

        emit SubgraphPublished(subgraphID, _subgraphDeploymentID, defaultReserveRatio);
        emit SubgraphMetadataUpdated(subgraphID, _subgraphMetadata);
        emit SubgraphVersionUpdated(subgraphID, _subgraphDeploymentID, _versionMetadata);
    }

    /**
     * @dev Publish a new version of an existing subgraph.
     * @param _subgraphID Subgraph ID
     * @param _subgraphDeploymentID Subgraph deployment ID of the new version
     * @param _versionMetadata IPFS hash for the subgraph version metadata
     */
    function publishNewVersion(
        uint256 _subgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) external override notPaused onlySubgraphAuth(_subgraphID) {
        // Perform the upgrade from the current subgraph deployment to the new one.
        // This involves burning all signal from the old deployment and using the funds to buy
        // from the new deployment.
        // This will also make the change to target to the new deployment.

        // Subgraph check
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // New subgraph deployment must be non-empty
        require(_subgraphDeploymentID != 0, "GNS: Cannot set deploymentID to 0 in publish");

        // New subgraph deployment must be different than current
        require(
            _subgraphDeploymentID != subgraphData.subgraphDeploymentID,
            "GNS: Cannot publish a new version with the same subgraph deployment ID"
        );

        // This is to prevent the owner from front running its name curators signal by posting
        // its own signal ahead, bringing the name curators in, and dumping on them
        ICuration curation = curation();
        require(
            !curation.isCurated(_subgraphDeploymentID),
            "GNS: Owner cannot point to a subgraphID that has been pre-curated"
        );

        // Move all signal from previous version to new version
        // NOTE: We will only do this as long as there is signal on the subgraph
        if (subgraphData.nSignal > 0) {
            uint256 tokens;

            // Init old version
            _initOldVersion(subgraphData);

            tokens = curation.burn(
                subgraphData.versions[VersionType.Current].subgraphDeploymentID,
                subgraphData.versions[VersionType.Current].vSignal,
                0
            );

            if (_versionExists(subgraphData.versions[VersionType.New])) {
                tokens += curation.burn(
                    subgraphData.versions[VersionType.New].subgraphDeploymentID,
                    subgraphData.versions[VersionType.New].vSignal,
                    0
                );
            }

            // Take the owner cut of the curation tax, add it to the total
            // Upgrade is only callable by the owner, we assume then that msg.sender = owner
            address subgraphOwner = msg.sender;

            // Divide tokens in half
            uint256 tokensWithTax = _chargeOwnerTax(
                tokens,
                subgraphOwner,
                curation.curationTaxPercentage()
            ).div(2);

            // Mint half to old version
            (uint256 _vSignalOld, ) = curation.mint(
                subgraphData.subgraphDeploymentID,
                tokensWithTax,
                0
            );

            // Mint half to new version
            (uint256 _vSignalNew, ) = curation.mint(_subgraphDeploymentID, tokensWithTax, 0);

            uint256 vSignalTotal = _vSignalOld + _vSignalNew;

            // Update vSignal for versions
            subgraphData.versions[VersionType.Current].vSignal = _vSignalOld;
            subgraphData.versions[VersionType.New].vSignal = _vSignalNew;

            // Update subgraphData Signal
            subgraphData.vSignal = vSignalTotal;

            emit SubgraphUpgraded(
                _subgraphID,
                vSignalTotal,
                tokensWithTax.mul(2),
                _subgraphDeploymentID
            );
        }

        // Update versions
        subgraphData.versions[VersionType.Current].subgraphDeploymentID = subgraphData
            .subgraphDeploymentID;
        subgraphData.versions[VersionType.New].subgraphDeploymentID = _subgraphDeploymentID;

        // Update deployment ID
        subgraphData.subgraphDeploymentID = _subgraphDeploymentID;

        emit SubgraphVersionUpdated(_subgraphID, _subgraphDeploymentID, _versionMetadata);
    }

    /**
     * @dev Finalize the upgrade process between two versions belonging to a subgraph
     * @param _subgraphID Subgraph ID
     */
    function finalizeSubgraphUpgrade(uint256 _subgraphID)
        external
        override
        notPaused
        onlySubgraphAuth(_subgraphID)
    {
        // Subgraph check
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // Check new version exists
        require(
            subgraphData.versions[VersionType.New].vSignal != 0,
            "GNS: New version does not exist"
        );

        ICuration curation = curation();

        uint256 tokens;

        // Burn signal
        tokens = curation.burn(
            subgraphData.versions[VersionType.Current].subgraphDeploymentID,
            subgraphData.versions[VersionType.Current].vSignal,
            0
        );
        tokens += curation.burn(
            subgraphData.versions[VersionType.New].subgraphDeploymentID,
            subgraphData.versions[VersionType.New].vSignal,
            0
        );

        // Mint tokens
        (uint256 _vSignalTotal, ) = curation.mint(
            subgraphData.versions[VersionType.New].subgraphDeploymentID,
            tokens,
            0
        );

        // Get total nSignal
        uint256 nSignalTotal = vSignalToNSignal(_subgraphID, _vSignalTotal);

        // Update Current version
        subgraphData.versions[VersionType.Current].subgraphDeploymentID = subgraphData
            .versions[VersionType.New]
            .subgraphDeploymentID;
        subgraphData.versions[VersionType.Current].vSignal = _vSignalTotal;

        // Remove New version data
        subgraphData.versions[VersionType.New].subgraphDeploymentID = "";
        subgraphData.versions[VersionType.New].vSignal = 0;

        // Update subgraphData
        subgraphData.subgraphDeploymentID = subgraphData
            .versions[VersionType.New]
            .subgraphDeploymentID;
        subgraphData.nSignal = nSignalTotal;
        subgraphData.vSignal = _vSignalTotal;

        // TODO: These events might need to be updated
        emit SubgraphUpgradeFinalized(
            _subgraphID,
            subgraphData.subgraphDeploymentID,
            subgraphData.versions[VersionType.Current].vSignal
        );
    }

    /**
     * @dev Deprecate a subgraph. The bonding curve is destroyed, the vSignal is burned, and the GNS
     * contract holds the GRT from burning the vSignal, which all curators can withdraw manually.
     * Can only be done by the subgraph owner.
     * @param _subgraphID Subgraph ID
     */
    function deprecateSubgraph(uint256 _subgraphID)
        external
        override
        notPaused
        onlySubgraphAuth(_subgraphID)
    {
        // Subgraph check
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // Init old version
        _initOldVersion(subgraphData);

        uint256 _withdrawableGRT;

        if (subgraphData.nSignal > 0) {
            _withdrawableGRT = curation().burn(
                subgraphData.versions[VersionType.Current].subgraphDeploymentID,
                subgraphData.versions[VersionType.Current].vSignal,
                0
            );

            subgraphData.versions[VersionType.Current].vSignal = 0;

            // If new version exists
            if (_versionExists(subgraphData.versions[VersionType.New])) {
                _withdrawableGRT += curation().burn(
                    subgraphData.versions[VersionType.New].subgraphDeploymentID,
                    subgraphData.versions[VersionType.New].vSignal,
                    0
                );

                subgraphData.versions[VersionType.New].vSignal = 0;
            }

            subgraphData.withdrawableGRT = _withdrawableGRT;
        }

        // Deprecate the subgraph and do cleanup
        subgraphData.disabled = true;
        subgraphData.vSignal = 0;
        subgraphData.reserveRatio = 0;
        // NOTE: We don't reset the following variable as we use it to test if the Subgraph was ever created
        // subgraphData.subgraphDeploymentID = 0;

        // Burn the NFT
        _burn(_subgraphID);

        emit SubgraphDeprecated(_subgraphID, subgraphData.withdrawableGRT);
    }

    /**
     * @dev Deposit GRT into a subgraph and mint signal.
     * @param _subgraphID Subgraph ID
     * @param _tokensIn The amount of tokens the nameCurator wants to deposit
     * @param _nSignalOutMin Expected minimum amount of name signal to receive
     */
    function mintSignal(
        uint256 _subgraphID,
        uint256 _tokensIn,
        uint256 _nSignalOutMin
    ) external override notPartialPaused {
        // Subgraph checks
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // Init old version
        _initOldVersion(subgraphData);

        address curator = msg.sender;
        uint256 _tokens = _tokensIn;

        // Pull tokens from sender
        TokenUtils.pullTokens(graphToken(), curator, _tokensIn);

        uint256 vSignalTotal;

        // If new version exists
        if (_versionExists(subgraphData.versions[VersionType.New])) {
            _tokens = _tokens.div(2);

            (vSignalTotal, ) = curation().mint(
                subgraphData.versions[VersionType.New].subgraphDeploymentID,
                _tokens,
                0
            );
            subgraphData.versions[VersionType.New].vSignal = subgraphData
                .versions[VersionType.New]
                .vSignal
                .add(vSignalTotal);
        }

        // Get name signal to mint for tokens deposited
        (uint256 vSignalOld, ) = curation().mint(
            subgraphData.versions[VersionType.Current].subgraphDeploymentID,
            _tokens,
            0
        );
        vSignalTotal += vSignalOld;

        uint256 nSignalTotal = vSignalToNSignal(_subgraphID, vSignalTotal);

        // Slippage protection
        require(nSignalTotal >= _nSignalOutMin, "GNS: Slippage protection");

        // Update version vSignal
        subgraphData.versions[VersionType.Current].vSignal = subgraphData
            .versions[VersionType.Current]
            .vSignal
            .add(vSignalOld);

        // Update pools
        subgraphData.vSignal = subgraphData.vSignal.add(vSignalTotal);
        subgraphData.nSignal = subgraphData.nSignal.add(nSignalTotal);
        subgraphData.curatorNSignal[curator] = subgraphData.curatorNSignal[curator].add(
            nSignalTotal
        );

        emit SignalMinted(_subgraphID, curator, nSignalTotal, vSignalTotal, _tokensIn);
    }

    /**
     * @dev Burn signal for a subgraph and return the GRT.
     * @param _subgraphID Subgraph ID
     * @param _nSignal The amount of nSignal the nameCurator wants to burn
     * @param _tokensOutMin Expected minimum amount of tokens to receive
     */
    function burnSignal(
        uint256 _subgraphID,
        uint256 _nSignal,
        uint256 _tokensOutMin
    ) external override notPartialPaused {
        // Subgraph checks
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // Init old version
        _initOldVersion(subgraphData);

        // Curator balance checks
        address curator = msg.sender;
        uint256 curatorNSignal = subgraphData.curatorNSignal[curator];
        require(
            _nSignal <= curatorNSignal,
            "GNS: Curator cannot withdraw more nSignal than they have"
        );

        bool newVersionExists = _versionExists(subgraphData.versions[VersionType.New]);
        uint256 vSignal = nSignalToVSignal(_subgraphID, _nSignal);
        uint256 tokens;

        // If new version exists
        if (newVersionExists) {
            vSignal = vSignal.div(2);

            tokens = curation().burn(
                subgraphData.versions[VersionType.New].subgraphDeploymentID,
                vSignal,
                _tokensOutMin
            );

            subgraphData.versions[VersionType.New].vSignal = subgraphData
                .versions[VersionType.New]
                .vSignal
                .sub(vSignal);
        }

        tokens += curation().burn(
            subgraphData.versions[VersionType.Current].subgraphDeploymentID,
            vSignal,
            _tokensOutMin
        );

        // Update version vSignal
        subgraphData.versions[VersionType.Current].vSignal = subgraphData
            .versions[VersionType.Current]
            .vSignal
            .sub(vSignal);

        if (newVersionExists) {
            vSignal = vSignal.mul(2);
        }

        // Update pools
        subgraphData.vSignal = subgraphData.vSignal.sub(vSignal);
        subgraphData.nSignal = subgraphData.nSignal.sub(_nSignal);
        subgraphData.curatorNSignal[curator] = subgraphData.curatorNSignal[curator].sub(_nSignal);

        // Return the tokens to the nameCurator
        require(graphToken().transfer(curator, tokens), "GNS: Error sending tokens");

        emit SignalBurned(_subgraphID, curator, _nSignal, vSignal, tokens);
    }

    /**
     * @dev Withdraw tokens from a deprecated subgraph.
     * When the subgraph is deprecated, any curator can call this function and
     * withdraw the GRT they are entitled for its original deposit
     * @param _subgraphID Subgraph ID
     */
    function withdraw(uint256 _subgraphID) external override notPartialPaused {
        // Subgraph validations
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        require(subgraphData.disabled == true, "GNS: Must be disabled first");
        require(subgraphData.withdrawableGRT > 0, "GNS: No more GRT to withdraw");

        // Curator validations
        address curator = msg.sender;
        uint256 curatorNSignal = subgraphData.curatorNSignal[curator];
        require(curatorNSignal > 0, "GNS: No signal to withdraw GRT");

        // Get curator share of tokens to be withdrawn
        uint256 tokensOut = curatorNSignal.mul(subgraphData.withdrawableGRT).div(
            subgraphData.nSignal
        );
        subgraphData.curatorNSignal[curator] = 0;
        subgraphData.nSignal = subgraphData.nSignal.sub(curatorNSignal);
        subgraphData.withdrawableGRT = subgraphData.withdrawableGRT.sub(tokensOut);

        // Return tokens to the curator
        TokenUtils.pushTokens(graphToken(), curator, tokensOut);

        emit GRTWithdrawn(_subgraphID, curator, curatorNSignal, tokensOut);
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
     * @dev Calculate subgraph signal to be returned for an amount of tokens.
     * @param _subgraphID Subgraph ID
     * @param _tokensIn Tokens being exchanged for subgraph signal
     * @return Amount of subgraph signal and curation tax
     */
    function tokensToNSignal(uint256 _subgraphID, uint256 _tokensIn)
        public
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);

        uint256 vSignalTotal;

        // If new version exists
        if (_versionExists(subgraphData.versions[VersionType.New])) {
            (uint256 vSignalNew, ) = curation().tokensToSignal(
                subgraphData.versions[VersionType.New].subgraphDeploymentID,
                _tokensIn
            );

            vSignalTotal += vSignalNew;
        }

        (uint256 vSignalOld, uint256 curationTax) = curation().tokensToSignal(
            subgraphData.versions[VersionType.Current].subgraphDeploymentID,
            _tokensIn
        );

        vSignalTotal += vSignalOld;

        uint256 nSignal = vSignalToNSignal(_subgraphID, vSignalTotal);

        // TODO: maybe pass both curationTaxes
        return (vSignalTotal, nSignal, curationTax);
    }

    /**
     * @dev Calculate tokens returned for an amount of subgraph signal.
     * @param _subgraphID Subgraph ID
     * @param _nSignalIn Subgraph signal being exchanged for tokens
     * @return Amount of tokens returned for an amount of subgraph signal
     */
    function nSignalToTokens(uint256 _subgraphID, uint256 _nSignalIn)
        public
        view
        override
        returns (uint256, uint256)
    {
        // Get subgraph or revert if not published
        // It does not make sense to convert signal from a disabled or non-existing one
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        uint256 vSignal = nSignalToVSignal(_subgraphID, _nSignalIn);
        uint256 tokensOut;

        if (_versionExists(subgraphData.versions[VersionType.New])) {
            // Divide signal in half
            vSignal = vSignal.div(2);

            tokensOut += curation().signalToTokens(
                subgraphData.versions[VersionType.New].subgraphDeploymentID,
                vSignal
            );
        }

        bytes32 subgraphDeploymentID;

        if (_versionExists(subgraphData.versions[VersionType.Current])) {
            subgraphDeploymentID = subgraphData.versions[VersionType.Current].subgraphDeploymentID;
        } else {
            subgraphDeploymentID = subgraphData.subgraphDeploymentID;
        }

        tokensOut += curation().signalToTokens(subgraphDeploymentID, vSignal);

        return (vSignal, tokensOut);
    }

    /**
     * @dev Calculate subgraph signal to be returned for an amount of subgraph deployment signal.
     * @param _subgraphID Subgraph ID
     * @param _vSignalIn Amount of subgraph deployment signal to exchange for subgraph signal
     * @return Amount of subgraph signal that can be bought
     */
    function vSignalToNSignal(uint256 _subgraphID, uint256 _vSignalIn)
        public
        view
        override
        returns (uint256)
    {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);

        // Handle initialization by using 1:1 version to name signal
        if (subgraphData.vSignal == 0) {
            return _vSignalIn;
        }

        return
            BancorFormula(bondingCurve).calculatePurchaseReturn(
                subgraphData.nSignal,
                subgraphData.vSignal,
                subgraphData.reserveRatio,
                _vSignalIn
            );
    }

    /**
     * @dev Calculate subgraph deployment signal to be returned for an amount of subgraph signal.
     * @param _subgraphID Subgraph ID
     * @param _nSignalIn Subgraph signal being exchanged for subgraph deployment signal
     * @return Amount of subgraph deployment signal that can be returned
     */
    function nSignalToVSignal(uint256 _subgraphID, uint256 _nSignalIn)
        public
        view
        override
        returns (uint256)
    {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        return
            BancorFormula(bondingCurve).calculateSaleReturn(
                subgraphData.nSignal,
                subgraphData.vSignal,
                subgraphData.reserveRatio,
                _nSignalIn
            );
    }

    /**
     * @dev Get the amount of subgraph signal a curator has.
     * @param _subgraphID Subgraph ID
     * @param _curator Curator address
     * @return Amount of subgraph signal owned by a curator
     */
    function getCuratorSignal(uint256 _subgraphID, address _curator)
        public
        view
        override
        returns (uint256)
    {
        return _getSubgraphData(_subgraphID).curatorNSignal[_curator];
    }

    /**
     * @dev Get the version subgraphDeploymentID and vSignal.
     * @param _subgraphID Subgraph ID
     * @param _version Version uint256
     * @return Version struct properties
     */
    function getSubgraphVersion(uint256 _subgraphID, VersionType _version)
        public
        view
        override
        returns (bytes32, uint256)
    {
        Version memory v = _getSubgraphData(_subgraphID).versions[_version];

        return (v.subgraphDeploymentID, v.vSignal);
    }

    /**
     * @dev Return the total signal on the subgraph.
     * @param _subgraphID Subgraph ID
     * @return Total signal on the subgraph
     */
    function subgraphSignal(uint256 _subgraphID) external view override returns (uint256) {
        return _getSubgraphData(_subgraphID).nSignal;
    }

    /**
     * @dev Return the total tokens on the subgraph at current value.
     * @param _subgraphID Subgraph ID
     * @return Total tokens on the subgraph
     */
    function subgraphTokens(uint256 _subgraphID) external view override returns (uint256) {
        uint256 signal = _getSubgraphData(_subgraphID).nSignal;
        if (signal > 0) {
            (, uint256 tokens) = nSignalToTokens(_subgraphID, signal);
            return tokens;
        }
        return 0;
    }

    /**
     * @dev Return the URI describing a particular token ID for a Subgraph.
     * @param _subgraphID Subgraph ID
     * @return The URI of the ERC721-compliant metadata
     */
    function tokenURI(uint256 _subgraphID) public view override returns (string memory) {
        return tokenDescriptor.tokenURI(this, _subgraphID);
    }

    /**
     * @dev Create subgraphID for legacy subgraph and mint ownership NFT.
     * @param _graphAccount Account that created the subgraph
     * @param _subgraphNumber The sequence number of the created subgraph
     */
    function migrateLegacySubgraph(address _graphAccount, uint256 _subgraphNumber) external {
        // Must be an existing legacy subgraph
        bool legacySubgraphExists = legacySubgraphData[_graphAccount][_subgraphNumber]
            .subgraphDeploymentID != 0;
        require(legacySubgraphExists == true, "GNS: Subgraph does not exist");

        // Must not be a claimed subgraph
        uint256 subgraphID = _buildSubgraphID(_graphAccount, _subgraphNumber);
        require(
            legacySubgraphKeys[subgraphID].account == address(0),
            "GNS: Subgraph was already claimed"
        );

        // Store a reference for a legacy subgraph
        legacySubgraphKeys[subgraphID] = IGNS.LegacySubgraphKey({
            account: _graphAccount,
            accountSeqID: _subgraphNumber
        });

        // Delete state for legacy subgraph
        legacySubgraphs[_graphAccount][_subgraphNumber] = 0;

        // Mint the NFT and send to owner
        // The subgraph owner is the graph account that created it
        _mint(_graphAccount, subgraphID);

        emit LegacySubgraphClaimed(_graphAccount, _subgraphNumber);
    }

    /**
     * @dev Return whether a subgraph is published.
     * @param _subgraphID Subgraph ID
     * @return Return true if subgraph is currently published
     */
    function isPublished(uint256 _subgraphID) public view override returns (bool) {
        return _isPublished(_getSubgraphData(_subgraphID));
    }

    /**
     * @dev Build a subgraph ID based on the account creating it and a sequence number for that account.
     * Subgraph ID is the keccak hash of account+seqID
     * @return Subgraph ID
     */
    function _buildSubgraphID(address _account, uint256 _seqID) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_account, _seqID)));
    }

    /**
     * @dev Return the next subgraphID given the account that is creating the subgraph.
     * NOTE: This function updates the sequence ID for the account
     * @return Sequence ID for the account
     */
    function _nextSubgraphID(address _account) internal returns (uint256) {
        return _buildSubgraphID(_account, _nextAccountSeqID(_account));
    }

    /**
     * @dev Return a new consecutive sequence ID for an account and update to the next value.
     * NOTE: This function updates the sequence ID for the account
     * @return Sequence ID for the account
     */
    function _nextAccountSeqID(address _account) internal returns (uint256) {
        uint256 seqID = nextAccountSeqID[_account];
        nextAccountSeqID[_account] = nextAccountSeqID[_account].add(1);
        return seqID;
    }

    /**
     * @dev Get subgraph data.
     * This function will first look for a v1 subgraph and return it if found.
     * @param _subgraphID Subgraph ID
     * @return Subgraph Data
     */
    function _getSubgraphData(uint256 _subgraphID) private view returns (SubgraphData storage) {
        // If there is a legacy subgraph created return it
        LegacySubgraphKey storage legacySubgraphKey = legacySubgraphKeys[_subgraphID];
        if (legacySubgraphKey.account != address(0)) {
            return legacySubgraphData[legacySubgraphKey.account][legacySubgraphKey.accountSeqID];
        }
        // Return new subgraph type
        return subgraphs[_subgraphID];
    }

    /**
     * @dev Return whether a subgraph is published.
     * @param _subgraphData Subgraph Data
     * @return Return true if subgraph is currently published
     */
    function _isPublished(SubgraphData storage _subgraphData) internal view returns (bool) {
        return _subgraphData.subgraphDeploymentID != 0 && _subgraphData.disabled == false;
    }

    /**
     * @dev Return the subgraph data or revert if not published or deprecated.
     * @param _subgraphID Subgraph ID
     * @return Subgraph Data
     */
    function _getSubgraphOrRevert(uint256 _subgraphID)
        internal
        view
        returns (SubgraphData storage)
    {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        require(_isPublished(subgraphData) == true, "GNS: Must be active");
        return subgraphData;
    }

    /**
     * @dev Check to see if verrsion exists
     * @param _version Version data
     * @return Bool Whether the version exists or not
     */
    function _versionExists(Version storage _version) internal view returns (bool) {
        return _version.subgraphDeploymentID != 0;
    }

    /**
     * @dev Initialize current version
     * @param _subgraphData Subgraph data
     */
    function _initOldVersion(SubgraphData storage _subgraphData) internal {
        if (!_versionExists(_subgraphData.versions[VersionType.Current])) {
            _subgraphData.versions[VersionType.Current].subgraphDeploymentID = _subgraphData
                .subgraphDeploymentID;
            _subgraphData.versions[VersionType.Current].vSignal = _subgraphData.vSignal;
        }
    }
}
