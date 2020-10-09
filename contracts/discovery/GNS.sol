pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../governance/Managed.sol";
import "../bancor/BancorFormula.sol";

import "./IGNS.sol";
import "./erc1056/IEthereumDIDRegistry.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized namings system for subgraphs
 * used in the scope of the Graph Network. It translates subgraph names into subgraph versions.
 * Each version is associated with a Subgraph Deployment. The contract no knowledge of human
 * readable names. All human readable names emitted in events.
 */
contract GNS is Managed, IGNS {
    using SafeMath for uint256;

    // -- State --

    // Equates to Connector weight on bancor formula to be CW = 1
    uint32 private constant defaultReserveRatio = 1000000;

    // In parts per hundred
    uint32 public ownerFeePercentage = 50;

    // Bonding curve formula
    address public bondingCurve;

    // Amount of nSignal you get with your minimum vSignal stake
    uint256 private constant VSIGNAL_PER_MINIMUM_NSIGNAL = 1 ether;

    // Minimum amount of vSignal that must be staked to start the curve
    // Set to 10**18, as vSignal has 18 decimals
    uint256 public minimumVSignalStake = 10**18;

    // graphAccountID => subgraphNumber => subgraphDeploymentID
    // subgraphNumber = A number associated to a graph accounts deployed subgraph. This
    //                  is used to point to a subgraphID (graphAccountID + subgraphNumber)
    mapping(address => mapping(uint256 => bytes32)) public subgraphs;

    // graphAccountID => subgraph deployment counter
    mapping(address => uint256) public graphAccountSubgraphNumbers;

    // graphAccountID => subgraphNumber => NameCurationPool
    mapping(address => mapping(uint256 => NameCurationPool)) public nameSignals;

    // ERC-1056 contract reference
    IEthereumDIDRegistry public erc1056Registry;

    // -- Events --

    /**
     * @dev Emitted when graph account sets their default name
     */
    event SetDefaultName(
        address graphAccount,
        uint256 nameSystem, // only ENS for now
        bytes32 nameIdentifier,
        string name
    );

    /**
     * @dev Emitted when graph account sets a subgraphs metadata on IPFS
     */
    event SubgraphMetadataUpdated(
        address graphAccount,
        uint256 subgraphNumber,
        bytes32 subgraphMetadata
    );

    /**
     * @dev Emitted when a `graph account` publishes a `subgraph` with a `version`.
     * Every time this event is emitted, indicates a new version has been created.
     * The event also emits a `metadataHash` with subgraph details and version details.
     */
    event SubgraphPublished(
        address graphAccount,
        uint256 subgraphNumber,
        bytes32 subgraphDeploymentID,
        bytes32 versionMetadata
    );

    /**
     * @dev Emitted when a graph account deprecated one of their subgraphs
     */
    event SubgraphDeprecated(address graphAccount, uint256 subgraphNumber);

    /**
     * @dev Emitted when a graphAccount creates an nSignal bonding curve that
     * points to a subgraph deployment
     */
    event NameSignalEnabled(
        address graphAccount,
        uint256 subgraphNumber,
        bytes32 subgraphDeploymentID,
        uint32 reserveRatio
    );

    /**
     * @dev Emitted when a name curator deposits their vSignal into an nSignal curve to mint nSignal
     */
    event NSignalMinted(
        address graphAccount,
        uint256 subgraphNumber,
        address nameCurator,
        uint256 nSignalCreated,
        uint256 vSignalCreated,
        uint256 tokensDeposited
    );

    /**
     * @dev Emitted when a name curator burns their nSignal, which in turn burns
     * the vSignal, and receives GRT
     */
    event NSignalBurned(
        address graphAccount,
        uint256 subgraphNumber,
        address nameCurator,
        uint256 nSignalBurnt,
        uint256 vSignalBurnt,
        uint256 tokensReceived
    );

    /**
     * @dev Emitted when a graph account upgrades their nSignal curve to point to a new
     * subgraph deployment, burning all the old vSignal and depositing the GRT into the
     * new vSignal curve, creating new nSignal
     */
    event NameSignalUpgrade(
        address graphAccount,
        uint256 subgraphNumber,
        uint256 newVSignalCreated,
        uint256 tokensSignalled,
        bytes32 subgraphDeploymentID
    );

    /**
     * @dev Emitted when an nSignal curve has been permanently disabled
     */
    event NameSignalDisabled(address graphAccount, uint256 subgraphNumber, uint256 withdrawableGRT);

    /**
     * @dev Emitted when a nameCurator withdraws their GRT from a deprecated name signal pool
     */
    event GRTWithdrawn(
        address graphAccount,
        uint256 subgraphNumber,
        address nameCurator,
        uint256 nSignalBurnt,
        uint256 withdrawnGRT
    );

    /**
    @dev Modifier that allows a function to be called by owner of a graph account
    @param _graphAccount Address of the graph account
    */
    modifier onlyGraphAccountOwner(address _graphAccount) {
        address graphAccountOwner = erc1056Registry.identityOwner(_graphAccount);
        require(graphAccountOwner == msg.sender, "GNS: Only graph account owner can call");
        _;
    }

    /**
     * @dev Contract Constructor.
     * @param _bondingCurve Contract that provides the bonding curve formula to use
     * @param _didRegistry Address of the Ethereum DID registry
     */
    constructor(
        address _controller,
        address _bondingCurve,
        address _didRegistry
    ) public {
        Managed._initialize(_controller);
        bondingCurve = _bondingCurve;
        erc1056Registry = IEthereumDIDRegistry(_didRegistry);
    }

    /**
     * @dev Approve curation contract to pull funds.
     */
    function approveAll() external override onlyGovernor {
        graphToken().approve(address(curation()), uint256(-1));
    }

    /**
     * @dev Set the minimum vSignal to be staked to create nSignal
     * @notice Update the minimum vSignal amount to `_minimumVSignalStake`
     * @param _minimumVSignalStake Minimum amount of vSignal required
     */
    function setMinimumVsignal(uint256 _minimumVSignalStake) external override onlyGovernor {
        require(_minimumVSignalStake > 0, "Minimum vSignal cannot be 0");
        minimumVSignalStake = _minimumVSignalStake;
        emit ParameterUpdated("minimumVSignalStake");
    }

    /**
     * @dev Set the owner fee percentage. This is used to prevent a subgraph owner to drain all
     * the name curators tokens while upgrading or deprecating and is configurable in parts per hundred.
     * @param _ownerFeePercentage Owner fee percentage
     */
    function setOwnerFeePercentage(uint32 _ownerFeePercentage) external override onlyGovernor {
        require(_ownerFeePercentage <= 100, "Owner fee must be 100 or less");
        ownerFeePercentage = _ownerFeePercentage;
        emit ParameterUpdated("ownerFeePercentage");
    }

    /**
     * @dev Allows a graph account to set a default name
     * @param _graphAccount Account that is setting their name
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
        graphAccountSubgraphNumbers[_graphAccount]++;
        updateSubgraphMetadata(_graphAccount, subgraphNumber, _subgraphMetadata);
        _enableNameSignal(_graphAccount, subgraphNumber);
    }

    /**
     * @dev Allows a graph account to publish a new version of their subgraph.
     * Version is derived from the occurance of SubgraphPublished being emitted.
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
     * @param _graphAccount Account that is publishing the subgraph
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
    function _enableNameSignal(address _graphAccount, uint256 _subgraphNumber) private {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        bytes32 subgraphDeploymentID = subgraphs[_graphAccount][_subgraphNumber];
        namePool.reserveRatio = defaultReserveRatio;
        namePool.subgraphDeploymentID = subgraphDeploymentID;
        emit NameSignalEnabled(
            _graphAccount,
            _subgraphNumber,
            subgraphDeploymentID,
            defaultReserveRatio
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
        // This is to prevent the owner from front running their name curators signal by posting
        // their own signal ahead, bringing the name curators in, and dumping on them
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

        uint256 vSignalOld = nSignalToVSignal(_graphAccount, _subgraphNumber, namePool.nSignal);
        (uint256 tokens, , uint256 ownerFee) = _burnVSignal(
            _graphAccount,
            namePool.subgraphDeploymentID,
            vSignalOld
        );
        namePool.vSignal = namePool.vSignal.sub(vSignalOld);
        // Update name signals deployment ID to match the subgraphs deployment ID
        namePool.subgraphDeploymentID = _newSubgraphDeploymentID;
        // nSignal stays constant, but vSignal can change here
        namePool.vSignal = curation.mint(namePool.subgraphDeploymentID, (tokens + ownerFee), 0);

        emit NameSignalUpgrade(
            _graphAccount,
            _subgraphNumber,
            namePool.vSignal,
            tokens + ownerFee,
            _newSubgraphDeploymentID
        );
    }

    /**
     * @dev Allow a name curator to mint some nSignal by depositing GRT
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number
     * @param _tokens The amount of tokens the nameCurator wants to deposit
     */
    function mintNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _tokens
    ) external override notPartialPaused {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(namePool.disabled == false, "GNS: Cannot be disabled");
        require(
            namePool.subgraphDeploymentID != 0,
            "GNS: Must deposit on a name signal that exists"
        );
        _mintNSignal(_graphAccount, _subgraphNumber, _tokens);
    }

    /**
     * @dev Allow a nameCurator to burn some of their nSignal and get GRT in return
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _nSignal The amount of nSignal the nameCurator wants to burn
     */
    function burnNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignal
    ) external override notPartialPaused {
        address nameCurator = msg.sender;
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 curatorNSignal = namePool.curatorNSignal[nameCurator];
        require(namePool.disabled == false, "GNS: Cannot be disabled");
        require(
            _nSignal <= curatorNSignal,
            "GNS: Curator cannot withdraw more nSignal than they have"
        );
        _burnNSignal(_graphAccount, _subgraphNumber, _nSignal);
    }

    /**
     * @dev Owner disables the subgraph. This means the subgraph-number combination can no longer
     * be used for name signal. The nSignal curve is destroyed, the vSignal is burned, and the GNS
     * contract holds the GRT from burning the vSignal, which all curators can withdraw manually.
     * @param _graphAccount Account that is deprecating their name curation
     * @param _subgraphNumber Subgraph number
     */
    function _disableNameSignal(address _graphAccount, uint256 _subgraphNumber) private {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        // If no nSignal, then no need to burn vSignal
        if (namePool.nSignal != 0) {
            (uint256 tokens, , uint256 ownerFee) = _burnVSignal(
                _graphAccount,
                namePool.subgraphDeploymentID,
                namePool.vSignal
            );
            namePool.vSignal = 0;
            namePool.withdrawableGRT = tokens + ownerFee;
        }
        // Set the NameCurationPool fields to make it disabled
        namePool.disabled = true;
        emit NameSignalDisabled(_graphAccount, _subgraphNumber, namePool.withdrawableGRT);
    }

    /**
     * @dev When the subgraph curve is disabled, all nameCurators can call this function and
     * withdraw the GRT they are entitled for their original deposit of vSignal
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     */
    function withdraw(address _graphAccount, uint256 _subgraphNumber)
        external
        override
        notPartialPaused
    {
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(namePool.disabled == true, "GNS: Name bonding curve must be disabled first");
        require(namePool.withdrawableGRT > 0, "GNS: No more GRT to withdraw");
        uint256 curatorNSignal = namePool.curatorNSignal[msg.sender];
        require(curatorNSignal > 0, "GNS: Curator must have some nSignal to withdraw GRT");
        uint256 tokens = curatorNSignal.mul(namePool.withdrawableGRT).div(namePool.nSignal);
        namePool.curatorNSignal[msg.sender] = 0;
        namePool.nSignal = namePool.nSignal.sub(curatorNSignal);
        namePool.withdrawableGRT = namePool.withdrawableGRT.sub(tokens);
        require(
            graphToken().transfer(msg.sender, tokens),
            "GNS: Error withdrawing tokens for nameCurator"
        );
        emit GRTWithdrawn(_graphAccount, _subgraphNumber, msg.sender, curatorNSignal, tokens);
    }

    /**
     * @dev Calculations for buying name signal
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _tokens GRT being deposited into vSignal to create nSignal
     * @return vSignal and tokens
     */
    function _mintNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _tokens
    ) private returns (uint256, uint256) {
        require(
            graphToken().transferFrom(msg.sender, address(this), _tokens),
            "GNS: Cannot transfer tokens to mint n signal"
        );
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = curation().mint(namePool.subgraphDeploymentID, _tokens, 0);
        uint256 nSignal = vSignalToNSignal(_graphAccount, _subgraphNumber, vSignal);
        namePool.vSignal = namePool.vSignal.add(vSignal);
        namePool.nSignal = namePool.nSignal.add(nSignal);
        namePool.curatorNSignal[msg.sender] = namePool.curatorNSignal[msg.sender].add(nSignal);
        emit NSignalMinted(_graphAccount, _subgraphNumber, msg.sender, nSignal, vSignal, _tokens);
        return (vSignal, nSignal);
    }

    /**
     * @dev Calculations for burning name signal
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _nSignal nSignal being burnt to receive vSignal to be burnt into GRT
     * @return vSignal and nSignal
     */
    function _burnNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignal
    ) private returns (uint256, uint256) {
        address nameCurator = msg.sender;
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = nSignalToVSignal(_graphAccount, _subgraphNumber, _nSignal);
        (uint256 tokens, ) = curation().burn(namePool.subgraphDeploymentID, vSignal, 0);
        namePool.vSignal = namePool.vSignal.sub(vSignal);
        namePool.nSignal = namePool.nSignal.sub(_nSignal);
        namePool.curatorNSignal[msg.sender] = namePool.curatorNSignal[msg.sender].sub(_nSignal);
        // Return the tokens to the nameCurator
        require(
            graphToken().transfer(nameCurator, tokens),
            "GNS: Error sending nameCurators tokens"
        );
        emit NSignalBurned(_graphAccount, _subgraphNumber, msg.sender, _nSignal, vSignal, tokens);
        return (vSignal, tokens);
    }

    /**
     * @dev Calculations burning vSignal from disabled or upgrade, while keeping n signal constant.
     * Takes the withdrawal fee from the name owner so they cannot grief all the name curators
     * @param _graphAccount Subgraph owner
     * @param _subgraphDeploymentID Subgraph deployment to burn all vSignal from
     * @param _vSignal vSignal being burnt
     * @return Tokens returned to the gns contract, withdrawal fees charged, and the owner fee
     * that the owner reimbursed from the withdrawal fee
     */
    function _burnVSignal(
        address _graphAccount,
        bytes32 _subgraphDeploymentID,
        uint256 _vSignal
    )
        private
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 tokens, uint256 withdrawalFees) = curation().burn(
            _subgraphDeploymentID,
            _vSignal,
            0
        );
        uint256 ownerFee = _chargeOwnerFee(withdrawalFees, _graphAccount);
        return (tokens, withdrawalFees, ownerFee);
    }

    /**
     * @dev Calculate fee that owner will have to cover for upgrading or deprecating
     * @param _owner Subgraph owner
     * @param _withdrawalFees Total withdrawal fee for changing subgraphs
     * @return Amount the owner must pay by transferring GRT to the GNS
     */
    function _chargeOwnerFee(uint256 _withdrawalFees, address _owner) private returns (uint256) {
        if (ownerFeePercentage == 0) {
            return 0;
        }
        uint256 ownerFee = _withdrawalFees.mul(ownerFeePercentage).div(100);
        // Get the owner of the Name to reimburse the withdrawal fee
        require(
            graphToken().transferFrom(_owner, address(this), ownerFee),
            "GNS: Error reimbursing withdrawal fees"
        );
        return ownerFee;
    }

    /**
     * @dev Calculate nSignal to be returned for an amount of tokens
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _tokens Tokens being exchanged for nSignal
     * @return Amount of vSignal and nSignal that can be returned
     */
    function tokensToNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _tokens
    ) public override view returns (uint256, uint256) {
        NameCurationPool memory namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = curation().tokensToSignal(namePool.subgraphDeploymentID, _tokens);
        uint256 nSignal = vSignalToNSignal(_graphAccount, _subgraphNumber, vSignal);
        return (vSignal, nSignal);
    }

    /**
     * @dev Calculate n signal to be returned for an amount of tokens
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _nSignal nSignal being exchanged for tokens
     * @return Amount of vSignal and tokens that can be returned
     */
    function nSignalToTokens(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignal
    )
        public
        override
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        NameCurationPool memory namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = nSignalToVSignal(_graphAccount, _subgraphNumber, _nSignal);
        (uint256 tokens, uint256 withdrawalFees) = curation().signalToTokens(
            namePool.subgraphDeploymentID,
            vSignal
        );
        return (vSignal, tokens, withdrawalFees);
    }

    /**
     * @dev Calculate nSignal to be returned for an amount of vSignal
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _vSignal being used for calculation
     * @return Amount of nSignal that can be bought
     */
    function vSignalToNSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _vSignal
    ) public override view returns (uint256) {
        NameCurationPool memory namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = _vSignal;

        // Handle initialization of bonding curve
        if (namePool.vSignal == 0) {
            return
                BancorFormula(bondingCurve)
                    .calculatePurchaseReturn(
                    VSIGNAL_PER_MINIMUM_NSIGNAL,
                    minimumVSignalStake,
                    defaultReserveRatio,
                    vSignal.sub(minimumVSignalStake)
                )
                    .add(VSIGNAL_PER_MINIMUM_NSIGNAL);
        }

        return
            BancorFormula(bondingCurve).calculatePurchaseReturn(
                namePool.nSignal,
                namePool.vSignal,
                namePool.reserveRatio,
                vSignal
            );
    }

    /**
     * @dev Calculate vSignal to be returned for an amount of nSignal
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     * @param _nSignal nSignal being exchanged for vSignal
     * @return Amount of vSignal that can be returned
     */
    function nSignalToVSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _nSignal
    ) public override view returns (uint256) {
        NameCurationPool memory namePool = nameSignals[_graphAccount][_subgraphNumber];
        return
            BancorFormula(bondingCurve).calculateSaleReturn(
                namePool.nSignal,
                namePool.vSignal,
                namePool.reserveRatio,
                _nSignal
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
    ) public override view returns (uint256) {
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
        override
        view
        returns (bool)
    {
        return subgraphs[_graphAccount][_subgraphNumber] != 0;
    }
}
