// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;
pragma abicoder v2;

// TODO: Re-enable and fix issues when publishing a new version
// solhint-disable function-max-lines, gas-indexed-events, gas-small-strings, gas-strict-inequalities

import { SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import { Multicall } from "../base/Multicall.sol";
import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";
import { ICuration } from "@graphprotocol/interfaces/contracts/contracts/curation/ICuration.sol";
import { Managed } from "../governance/Managed.sol";
import { ISubgraphNFT } from "@graphprotocol/interfaces/contracts/contracts/discovery/ISubgraphNFT.sol";

import { IGNS } from "@graphprotocol/interfaces/contracts/contracts/discovery/IGNS.sol";
import { GNSV3Storage } from "./GNSStorage.sol";

/**
 * @title GNS
 * @author Edge & Node
 * @notice The Graph Name System contract provides a decentralized naming system for subgraphs
 * used in the scope of the Graph Network. It translates Subgraphs into Subgraph Versions.
 * Each version is associated with a Subgraph Deployment. The contract has no knowledge of
 * human-readable names. All human readable names emitted in events.
 * The contract implements a multicall behaviour to support batching multiple calls in a single
 * transaction.
 */
abstract contract GNS is GNSV3Storage, GraphUpgradeable, IGNS, Multicall {
    using SafeMathUpgradeable for uint256;

    // -- Constants --

    /// @dev 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;

    /// @dev Equates to Connector weight on bancor formula to be CW = 1
    // solhint-disable-next-line immutable-vars-naming
    uint32 internal immutable fixedReserveRatio = MAX_PPM;

    // -- Events --

    /// @notice Emitted when the subgraph NFT contract is updated
    /// @param subgraphNFT Address of the new subgraph NFT contract
    event SubgraphNFTUpdated(address subgraphNFT);

    /**
     * @notice Emitted when graph account sets its default name
     * @param graphAccount Address of the graph account
     * @param nameSystem Name system identifier (only ENS for now)
     * @param nameIdentifier Name identifier in the name system
     * @param name Human-readable name
     */
    event SetDefaultName(
        address indexed graphAccount,
        uint256 nameSystem, // only ENS for now
        bytes32 nameIdentifier,
        string name
    );

    /**
     * @notice Emitted when the subgraph metadata is updated.
     * @param subgraphID ID of the subgraph
     * @param subgraphMetadata IPFS hash of the subgraph metadata
     */
    event SubgraphMetadataUpdated(uint256 indexed subgraphID, bytes32 subgraphMetadata);

    /**
     * @notice Emitted when a subgraph version is updated.
     * @param subgraphID ID of the subgraph
     * @param subgraphDeploymentID Subgraph deployment ID for the new version
     * @param versionMetadata IPFS hash of the version metadata
     */
    event SubgraphVersionUpdated(
        uint256 indexed subgraphID,
        bytes32 indexed subgraphDeploymentID,
        bytes32 versionMetadata
    );

    /**
     * @notice Emitted when a curator mints signal.
     * @param subgraphID ID of the subgraph
     * @param curator Address of the curator
     * @param nSignalCreated Amount of name signal created
     * @param vSignalCreated Amount of version signal created
     * @param tokensDeposited Amount of tokens deposited
     */
    event SignalMinted(
        uint256 indexed subgraphID,
        address indexed curator,
        uint256 nSignalCreated,
        uint256 vSignalCreated,
        uint256 tokensDeposited
    );

    /**
     * @notice Emitted when a curator burns signal.
     * @param subgraphID ID of the subgraph
     * @param curator Address of the curator
     * @param nSignalBurnt Amount of name signal burned
     * @param vSignalBurnt Amount of version signal burned
     * @param tokensReceived Amount of tokens received
     */
    event SignalBurned(
        uint256 indexed subgraphID,
        address indexed curator,
        uint256 nSignalBurnt,
        uint256 vSignalBurnt,
        uint256 tokensReceived
    );

    /**
     * @notice Emitted when a curator transfers signal.
     * @param subgraphID ID of the subgraph
     * @param from Address transferring the signal
     * @param to Address receiving the signal
     * @param nSignalTransferred Amount of name signal transferred
     */
    event SignalTransferred(
        uint256 indexed subgraphID,
        address indexed from,
        address indexed to,
        uint256 nSignalTransferred
    );

    /**
     * @notice Emitted when a subgraph is created.
     * @param subgraphID ID of the subgraph
     * @param subgraphDeploymentID Subgraph deployment ID
     * @param reserveRatio Reserve ratio for the bonding curve
     */
    event SubgraphPublished(uint256 indexed subgraphID, bytes32 indexed subgraphDeploymentID, uint32 reserveRatio);

    /**
     * @notice Emitted when a subgraph is upgraded to point to a new
     * subgraph deployment, burning all the old vSignal and depositing the GRT into the
     * new vSignal curve.
     * @param subgraphID ID of the subgraph
     * @param vSignalCreated Amount of version signal created in the new deployment
     * @param tokensSignalled Amount of tokens signalled in the new deployment
     * @param subgraphDeploymentID New subgraph deployment ID
     */
    event SubgraphUpgraded(
        uint256 indexed subgraphID,
        uint256 vSignalCreated,
        uint256 tokensSignalled,
        bytes32 indexed subgraphDeploymentID
    );

    /**
     * @notice Emitted when a subgraph is deprecated.
     * @param subgraphID ID of the subgraph
     * @param withdrawableGRT Amount of GRT available for withdrawal
     */
    event SubgraphDeprecated(uint256 indexed subgraphID, uint256 withdrawableGRT);

    /**
     * @notice Emitted when a curator withdraws GRT from a deprecated subgraph
     * @param subgraphID ID of the subgraph
     * @param curator Address of the curator
     * @param nSignalBurnt Amount of name signal burned
     * @param withdrawnGRT Amount of GRT withdrawn
     */
    event GRTWithdrawn(uint256 indexed subgraphID, address indexed curator, uint256 nSignalBurnt, uint256 withdrawnGRT);

    /**
     * @notice Emitted when the counterpart (L1/L2) GNS address is updated
     * @param _counterpart Address of the counterpart GNS contract
     */
    event CounterpartGNSAddressUpdated(address _counterpart);

    // -- Modifiers --

    /**
     * @notice Emitted when a legacy subgraph is claimed
     * @param graphAccount Address of the graph account that created the subgraph
     * @param subgraphNumber Sequence number of the subgraph
     */
    event LegacySubgraphClaimed(address indexed graphAccount, uint256 subgraphNumber);

    /**
     * @notice Modifier that allows only a subgraph operator to be the caller
     * @param _subgraphID ID of the subgraph to check authorization for
     */
    modifier onlySubgraphAuth(uint256 _subgraphID) {
        require(ownerOf(_subgraphID) == msg.sender, "GNS: Must be authorized");
        _;
    }

    // -- Functions --

    /**
     * @notice Initialize the GNS contract.
     * @param _controller Address of the Controller contract that manages this contract
     * @param _subgraphNFT Address of the Subgraph NFT contract
     */
    function initialize(address _controller, address _subgraphNFT) external onlyImpl initializer {
        Managed._initialize(_controller);

        // Settings
        _setOwnerTaxPercentage(500000);
        _setSubgraphNFT(_subgraphNFT);
    }

    /**
     * @inheritdoc IGNS
     */
    function approveAll() external override {
        graphToken().approve(address(curation()), type(uint256).max);
    }

    // -- Config --

    /**
     * @inheritdoc IGNS
     */
    function setOwnerTaxPercentage(uint32 _ownerTaxPercentage) external override onlyGovernor {
        _setOwnerTaxPercentage(_ownerTaxPercentage);
    }

    /**
     * @notice Set the NFT registry contract
     * NOTE: Calling this function will break the ownership model unless
     * it is replaced with a fully migrated version of the NFT contract state
     * Use with care.
     * @param _subgraphNFT Address of the ERC721 contract
     */
    function setSubgraphNFT(address _subgraphNFT) external onlyGovernor {
        _setSubgraphNFT(_subgraphNFT);
    }

    /**
     * @notice Set the counterpart (L1/L2) GNS address
     * @param _counterpart Owner tax percentage
     */
    function setCounterpartGNSAddress(address _counterpart) external onlyGovernor {
        counterpartGNSAddress = _counterpart;
        emit CounterpartGNSAddressUpdated(_counterpart);
    }

    // -- Actions --

    /**
     * @inheritdoc IGNS
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
     * @inheritdoc IGNS
     */
    function updateSubgraphMetadata(
        uint256 _subgraphID,
        bytes32 _subgraphMetadata
    ) external override onlySubgraphAuth(_subgraphID) {
        _setSubgraphMetadata(_subgraphID, _subgraphMetadata);
    }

    /**
     * @inheritdoc IGNS
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
        subgraphData.__DEPRECATED_reserveRatio = fixedReserveRatio;

        // Mint the NFT. Use the subgraphID as tokenID.
        // This function will check the if tokenID already exists.
        _mintNFT(subgraphOwner, subgraphID);
        emit SubgraphPublished(subgraphID, _subgraphDeploymentID, fixedReserveRatio);

        // Set the token metadata
        _setSubgraphMetadata(subgraphID, _subgraphMetadata);

        emit SubgraphVersionUpdated(subgraphID, _subgraphDeploymentID, _versionMetadata);
    }

    /**
     * @inheritdoc IGNS
     */
    function publishNewVersion(
        uint256 _subgraphID,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) external virtual override notPaused onlySubgraphAuth(_subgraphID) {
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
        if (subgraphData.nSignal != 0) {
            // Burn all version signal in the name pool for tokens (w/no slippage protection)
            // Sell all signal from the old deployment
            uint256 tokens = curation.burn(subgraphData.subgraphDeploymentID, subgraphData.vSignal, 0);

            // Take the owner cut of the curation tax, add it to the total
            // Upgrade is only callable by the owner, we assume then that msg.sender = owner
            address subgraphOwner = msg.sender;
            uint256 tokensWithTax = _chargeOwnerTax(tokens, subgraphOwner, curation.curationTaxPercentage());

            // Update pool: constant nSignal, vSignal can change (w/no slippage protection)
            // Buy all signal from the new deployment
            (subgraphData.vSignal, ) = curation.mint(_subgraphDeploymentID, tokensWithTax, 0);

            emit SubgraphUpgraded(_subgraphID, subgraphData.vSignal, tokensWithTax, _subgraphDeploymentID);
        }

        // Update target deployment
        subgraphData.subgraphDeploymentID = _subgraphDeploymentID;

        emit SubgraphVersionUpdated(_subgraphID, _subgraphDeploymentID, _versionMetadata);
    }

    /**
     * @inheritdoc IGNS
     * @notice The bonding curve is destroyed, the vSignal is burned, and the GNS
     * contract holds the GRT from burning the vSignal, which all curators can withdraw manually.
     * Can only be done by the subgraph owner.
     */
    function deprecateSubgraph(uint256 _subgraphID) external override notPaused onlySubgraphAuth(_subgraphID) {
        // Subgraph check
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // Burn signal only if it has any available
        if (subgraphData.nSignal != 0) {
            subgraphData.withdrawableGRT = curation().burn(subgraphData.subgraphDeploymentID, subgraphData.vSignal, 0);
        }

        // Deprecate the subgraph and do cleanup
        subgraphData.disabled = true;
        subgraphData.vSignal = 0;
        subgraphData.__DEPRECATED_reserveRatio = 0;
        // NOTE: We don't reset the following variable as we use it to test if the Subgraph was ever created
        // subgraphData.subgraphDeploymentID = 0;

        // Burn the NFT
        _burnNFT(_subgraphID);

        emit SubgraphDeprecated(_subgraphID, subgraphData.withdrawableGRT);
    }

    /**
     * @inheritdoc IGNS
     */
    function mintSignal(
        uint256 _subgraphID,
        uint256 _tokensIn,
        uint256 _nSignalOutMin
    ) external override notPartialPaused {
        // Subgraph checks
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // Pull tokens from sender
        address curator = msg.sender;
        TokenUtils.pullTokens(graphToken(), curator, _tokensIn);

        // Get name signal to mint for tokens deposited
        (uint256 vSignal, ) = curation().mint(subgraphData.subgraphDeploymentID, _tokensIn, 0);
        uint256 nSignal = vSignalToNSignal(_subgraphID, vSignal);

        // Slippage protection
        require(nSignal >= _nSignalOutMin, "GNS: Slippage protection");

        // Update pools
        subgraphData.vSignal = subgraphData.vSignal.add(vSignal);
        subgraphData.nSignal = subgraphData.nSignal.add(nSignal);
        subgraphData.curatorNSignal[curator] = subgraphData.curatorNSignal[curator].add(nSignal);

        emit SignalMinted(_subgraphID, curator, nSignal, vSignal, _tokensIn);
    }

    /**
     * @inheritdoc IGNS
     */
    function burnSignal(
        uint256 _subgraphID,
        uint256 _nSignal,
        uint256 _tokensOutMin
    ) external override notPartialPaused {
        // Subgraph checks
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // Curator balance checks
        address curator = msg.sender;
        uint256 curatorNSignal = subgraphData.curatorNSignal[curator];
        require(_nSignal <= curatorNSignal, "GNS: Curator cannot withdraw more nSignal than they have");

        // Get tokens for name signal amount to burn
        uint256 vSignal = nSignalToVSignal(_subgraphID, _nSignal);
        uint256 tokens = curation().burn(subgraphData.subgraphDeploymentID, vSignal, _tokensOutMin);

        // Update pools
        subgraphData.vSignal = subgraphData.vSignal.sub(vSignal);
        subgraphData.nSignal = subgraphData.nSignal.sub(_nSignal);
        subgraphData.curatorNSignal[curator] = subgraphData.curatorNSignal[curator].sub(_nSignal);

        // Return the tokens to the nameCurator
        require(graphToken().transfer(curator, tokens), "GNS: Error sending tokens");

        emit SignalBurned(_subgraphID, curator, _nSignal, vSignal, tokens);
    }

    /**
     * @notice Move subgraph signal from sender to `_recipient`
     * @param _subgraphID Subgraph ID
     * @param _recipient Address to send the signal to
     * @param _amount The amount of nSignal to transfer
     */
    function transferSignal(
        uint256 _subgraphID,
        address _recipient,
        uint256 _amount
    ) external override notPartialPaused {
        require(_recipient != address(0), "GNS: Curator cannot transfer to the zero address");

        // Subgraph checks
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);

        // Balance checks
        address curator = msg.sender;
        uint256 curatorBalance = subgraphData.curatorNSignal[curator];
        require(curatorBalance >= _amount, "GNS: Curator transfer amount exceeds balance");

        // Move the signal
        subgraphData.curatorNSignal[curator] = subgraphData.curatorNSignal[curator].sub(_amount);
        subgraphData.curatorNSignal[_recipient] = subgraphData.curatorNSignal[_recipient].add(_amount);

        emit SignalTransferred(_subgraphID, curator, _recipient, _amount);
    }

    /**
     * @notice Withdraw tokens from a deprecated subgraph.
     * When the subgraph is deprecated, any curator can call this function and
     * withdraw the GRT they are entitled for its original deposit
     * @param _subgraphID Subgraph ID
     */
    function withdraw(uint256 _subgraphID) external override notPartialPaused {
        // Subgraph validations
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        require(subgraphData.disabled == true, "GNS: Must be disabled first");
        require(subgraphData.withdrawableGRT != 0, "GNS: No more GRT to withdraw");

        // Curator validations
        address curator = msg.sender;
        uint256 curatorNSignal = subgraphData.curatorNSignal[curator];
        require(curatorNSignal != 0, "GNS: No signal to withdraw GRT");

        // Get curator share of tokens to be withdrawn
        uint256 tokensOut = curatorNSignal.mul(subgraphData.withdrawableGRT).div(subgraphData.nSignal);
        subgraphData.curatorNSignal[curator] = 0;
        subgraphData.nSignal = subgraphData.nSignal.sub(curatorNSignal);
        subgraphData.withdrawableGRT = subgraphData.withdrawableGRT.sub(tokensOut);

        // Return tokens to the curator
        TokenUtils.pushTokens(graphToken(), curator, tokensOut);

        emit GRTWithdrawn(_subgraphID, curator, curatorNSignal, tokensOut);
    }

    /**
     * @notice Create subgraphID for legacy subgraph and mint ownership NFT.
     * @param _graphAccount Account that created the subgraph
     * @param _subgraphNumber The sequence number of the created subgraph
     * @param _subgraphMetadata IPFS hash for the subgraph metadata
     */
    function migrateLegacySubgraph(address _graphAccount, uint256 _subgraphNumber, bytes32 _subgraphMetadata) external {
        // Must be an existing legacy subgraph
        bool legacySubgraphExists = legacySubgraphData[_graphAccount][_subgraphNumber].subgraphDeploymentID != 0;
        require(legacySubgraphExists == true, "GNS: Subgraph does not exist");

        // Must not be a claimed subgraph
        uint256 subgraphID = _buildLegacySubgraphID(_graphAccount, _subgraphNumber);
        require(legacySubgraphKeys[subgraphID].account == address(0), "GNS: Subgraph was already claimed");

        // Store a reference for a legacy subgraph
        legacySubgraphKeys[subgraphID] = IGNS.LegacySubgraphKey({
            account: _graphAccount,
            accountSeqID: _subgraphNumber
        });

        // Delete state for legacy subgraph
        legacySubgraphs[_graphAccount][_subgraphNumber] = 0;

        // Mint the NFT and send to owner
        // The subgraph owner is the graph account that created it
        _mintNFT(_graphAccount, subgraphID);
        emit LegacySubgraphClaimed(_graphAccount, _subgraphNumber);

        // Set the token metadata
        _setSubgraphMetadata(subgraphID, _subgraphMetadata);
    }

    /**
     * @notice Return the total signal on the subgraph.
     * @param _subgraphID Subgraph ID
     * @return Total signal on the subgraph
     */
    function subgraphSignal(uint256 _subgraphID) external view override returns (uint256) {
        return _getSubgraphData(_subgraphID).nSignal;
    }

    /**
     * @notice Return the total tokens on the subgraph at current value.
     * @param _subgraphID Subgraph ID
     * @return Total tokens on the subgraph
     */
    function subgraphTokens(uint256 _subgraphID) external view override returns (uint256) {
        uint256 signal = _getSubgraphData(_subgraphID).nSignal;
        if (signal != 0) {
            (, uint256 tokens) = nSignalToTokens(_subgraphID, signal);
            return tokens;
        }
        return 0;
    }

    /**
     * @notice Return whether a subgraph is a legacy subgraph (created before subgraph NFTs).
     * @param _subgraphID Subgraph ID
     * @return Return true if subgraph is a legacy subgraph
     */
    function isLegacySubgraph(uint256 _subgraphID) external view override returns (bool) {
        (address account, ) = getLegacySubgraphKey(_subgraphID);
        return account != address(0);
    }

    /**
     * @notice Calculate subgraph signal to be returned for an amount of tokens.
     * @param _subgraphID Subgraph ID
     * @param _tokensIn Tokens being exchanged for subgraph signal
     * @return nSignalOut Amount of name signal minted
     * @return curationTax Amount of curation tax charged
     * @return vSignalOut Amount of version signal minted
     */
    function tokensToNSignal(
        uint256 _subgraphID,
        uint256 _tokensIn
    ) public view override returns (uint256, uint256, uint256) {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        (uint256 vSignal, uint256 curationTax) = curation().tokensToSignal(
            subgraphData.subgraphDeploymentID,
            _tokensIn
        );
        uint256 nSignal = vSignalToNSignal(_subgraphID, vSignal);
        return (vSignal, nSignal, curationTax);
    }

    /**
     * @notice Calculate tokens returned for an amount of subgraph signal.
     * @param _subgraphID Subgraph ID
     * @param _nSignalIn Subgraph signal being exchanged for tokens
     * @return vSignalOut Amount of version signal burned
     * @return tokensOut Amount of tokens returned
     */
    function nSignalToTokens(uint256 _subgraphID, uint256 _nSignalIn) public view override returns (uint256, uint256) {
        // Get subgraph or revert if not published
        // It does not make sense to convert signal from a disabled or non-existing one
        SubgraphData storage subgraphData = _getSubgraphOrRevert(_subgraphID);
        uint256 vSignal = nSignalToVSignal(_subgraphID, _nSignalIn);
        uint256 tokensOut = curation().signalToTokens(subgraphData.subgraphDeploymentID, vSignal);
        return (vSignal, tokensOut);
    }

    /**
     * @inheritdoc IGNS
     */
    function vSignalToNSignal(uint256 _subgraphID, uint256 _vSignalIn) public view override returns (uint256) {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);

        // Handle initialization by using 1:1 version to name signal
        if (subgraphData.vSignal == 0) {
            return _vSignalIn;
        }

        return subgraphData.nSignal.mul(_vSignalIn).div(subgraphData.vSignal);
    }

    /**
     * @inheritdoc IGNS
     */
    function nSignalToVSignal(uint256 _subgraphID, uint256 _nSignalIn) public view override returns (uint256) {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        return subgraphData.vSignal.mul(_nSignalIn).div(subgraphData.nSignal);
    }

    /**
     * @inheritdoc IGNS
     */
    function getCuratorSignal(uint256 _subgraphID, address _curator) public view override returns (uint256) {
        return _getSubgraphData(_subgraphID).curatorNSignal[_curator];
    }

    /**
     * @inheritdoc IGNS
     */
    function isPublished(uint256 _subgraphID) public view override returns (bool) {
        return _isPublished(_getSubgraphData(_subgraphID));
    }

    /**
     * @inheritdoc IGNS
     */
    function getLegacySubgraphKey(uint256 _subgraphID) public view override returns (address account, uint256 seqID) {
        LegacySubgraphKey storage legacySubgraphKey = legacySubgraphKeys[_subgraphID];
        account = legacySubgraphKey.account;
        seqID = legacySubgraphKey.accountSeqID;
    }

    /**
     * @inheritdoc IGNS
     */
    function ownerOf(uint256 _tokenID) public view override returns (address) {
        return subgraphNFT.ownerOf(_tokenID);
    }

    /**
     * @notice Calculate tax that owner will have to cover for upgrading or deprecating.
     * @param _tokens Tokens that were received from deprecating the old subgraph
     * @param _owner Subgraph owner
     * @param _curationTaxPercentage Tax percentage on curation deposits from Curation contract
     * @return Total tokens that will be sent to curation, _tokens + ownerTax
     */
    function _chargeOwnerTax(
        uint256 _tokens,
        address _owner,
        uint32 _curationTaxPercentage
    ) internal returns (uint256) {
        // If curation or owner tax are zero, we don't need to charge owner tax
        // so the amount of tokens to signal will remain the same.
        // Note if owner tax is zero but curation tax is nonzero, the curation tax
        // will still be charged (in Curation or L2Curation) - this function just calculates
        // the owner's additional tax.
        if (_curationTaxPercentage == 0 || ownerTaxPercentage == 0) {
            return _tokens;
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
     * @notice Return the next subgraphID given the account that is creating the subgraph.
     * NOTE: This function updates the sequence ID for the account
     * @param _account The account creating the subgraph
     * @return Sequence ID for the account
     */
    function _nextSubgraphID(address _account) internal returns (uint256) {
        return _buildSubgraphID(_account, _nextAccountSeqID(_account));
    }

    /**
     * @notice Return a new consecutive sequence ID for an account and update to the next value.
     * NOTE: This function updates the sequence ID for the account
     * @param _account The account to get the next sequence ID for
     * @return Sequence ID for the account
     */
    function _nextAccountSeqID(address _account) internal returns (uint256) {
        uint256 seqID = nextAccountSeqID[_account];
        nextAccountSeqID[_account] = nextAccountSeqID[_account].add(1);
        return seqID;
    }

    /**
     * @notice Mint the NFT for the subgraph.
     * @param _owner Owner address
     * @param _tokenID Subgraph ID
     */
    function _mintNFT(address _owner, uint256 _tokenID) internal {
        subgraphNFT.mint(_owner, _tokenID);
    }

    /**
     * @notice Burn the NFT for the subgraph.
     * @param _tokenID Subgraph ID
     */
    function _burnNFT(uint256 _tokenID) internal {
        subgraphNFT.burn(_tokenID);
    }

    /**
     * @notice Set the subgraph metadata.
     * @param _tokenID Subgraph ID
     * @param _subgraphMetadata IPFS hash of the subgraph metadata
     */
    function _setSubgraphMetadata(uint256 _tokenID, bytes32 _subgraphMetadata) internal {
        subgraphNFT.setSubgraphMetadata(_tokenID, _subgraphMetadata);

        // Even if the following event is emitted in the NFT we emit it here to facilitate
        // subgraph indexing
        emit SubgraphMetadataUpdated(_tokenID, _subgraphMetadata);
    }

    /**
     * @notice Get subgraph data.
     * This function will first look for a v1 subgraph and return it if found.
     * @param _subgraphID Subgraph ID
     * @return Subgraph Data
     */
    function _getSubgraphData(uint256 _subgraphID) internal view virtual returns (SubgraphData storage) {
        // If there is a legacy subgraph created return it
        LegacySubgraphKey storage legacySubgraphKey = legacySubgraphKeys[_subgraphID];
        if (legacySubgraphKey.account != address(0)) {
            return legacySubgraphData[legacySubgraphKey.account][legacySubgraphKey.accountSeqID];
        }
        // Return new subgraph type
        return subgraphs[_subgraphID];
    }

    /**
     * @notice Return whether a subgraph is published.
     * @param _subgraphData Subgraph Data
     * @return Return true if subgraph is currently published
     */
    function _isPublished(SubgraphData storage _subgraphData) internal view returns (bool) {
        return _subgraphData.subgraphDeploymentID != 0 && _subgraphData.disabled == false;
    }

    /**
     * @notice Return the subgraph data or revert if not published or deprecated.
     * @param _subgraphID Subgraph ID
     * @return Subgraph Data
     */
    function _getSubgraphOrRevert(uint256 _subgraphID) internal view returns (SubgraphData storage) {
        SubgraphData storage subgraphData = _getSubgraphData(_subgraphID);
        require(_isPublished(subgraphData) == true, "GNS: Must be active");
        return subgraphData;
    }

    /**
     * @notice Build a subgraph ID based on the account creating it and a sequence number for that account.
     * Only used for legacy subgraphs being migrated, as new ones will also use the chainid.
     * Subgraph ID is the keccak hash of account+seqID
     * @param _account The account creating the subgraph
     * @param _seqID The sequence ID for the account
     * @return Subgraph ID
     */
    function _buildLegacySubgraphID(address _account, uint256 _seqID) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_account, _seqID)));
    }

    /**
     * @notice Build a subgraph ID based on the account creating it and a sequence number for that account.
     * Subgraph ID is the keccak hash of account+seqID
     * @param _account The account creating the subgraph
     * @param _seqID The sequence ID for the account
     * @return Subgraph ID
     */
    function _buildSubgraphID(address _account, uint256 _seqID) internal pure returns (uint256) {
        uint256 chainId;
        // Too bad solidity 0.7.6 still doesn't have block.chainid
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }
        return uint256(keccak256(abi.encodePacked(_account, _seqID, chainId)));
    }

    /**
     * @notice Internal: Set the owner tax percentage. This is used to prevent a subgraph owner to drain all
     * the name curators tokens while upgrading or deprecating and is configurable in parts per million.
     * @param _ownerTaxPercentage Owner tax percentage
     */
    function _setOwnerTaxPercentage(uint32 _ownerTaxPercentage) private {
        require(_ownerTaxPercentage <= MAX_PPM, "Owner tax must be MAX_PPM or less");
        ownerTaxPercentage = _ownerTaxPercentage;
        emit ParameterUpdated("ownerTaxPercentage");
    }

    /**
     * @notice Internal: Set the NFT registry contract
     * @param _subgraphNFT Address of the ERC721 contract
     */
    function _setSubgraphNFT(address _subgraphNFT) private {
        require(_subgraphNFT != address(0), "NFT address cant be zero");
        require(AddressUpgradeable.isContract(_subgraphNFT), "NFT must be valid");

        subgraphNFT = ISubgraphNFT(_subgraphNFT);
        emit SubgraphNFTUpdated(_subgraphNFT);
    }
}
