pragma solidity ^0.6.4;
pragma experimental ABIEncoderV2;

import "./governance/Governed.sol";
import "./curation/ICuration.sol";
import "./token/IGraphToken.sol";
import "./erc1056/IEthereumDIDRegistry.sol";
import "./bancor/BancorFormula.sol";

/**
 * @title GNS
 * @dev The Graph Name System contract provides a decentralized namings system for subgraphs
 * used in the scope of the Graph Network. It translates subgraph names into subgraph versions.
 * Each version is associated with a Subgraph Deployment. The contract no knowledge of human
 * readable names. All human readable names emitted in events.
 */
contract GNS is Governed, BancorFormula {
    // -- State --

    struct NameCurationPool {
        uint256 vSignal; // The token of the subgraph deployment bonding curve
        uint256 nSignal; // The token of the name curation bonding curve
        mapping(address => uint256) curatorNSignal;
        bytes32 subgraphDeploymentID;
        uint32 reserveRatio;
        bool disabled;
        uint256 withdrawableGRT;
    }

    // Equates to Connector weight on bancor formula to be CW = 1
    uint32 private constant defaultReserveRatio = 1000000;

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

    // Curation contract reference
    ICuration public curation;

    // Token used for staking
    IGraphToken public token;

    // -- Events --

    /**
     * @dev TODO
     */
    event SetDefaultName(
        address graphAccount,
        uint256 nameSystem, // only ENS for now
        bytes32 nameIdentifier,
        string name
    );

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
        uint256 vSignalCreated,
        uint256 nSignalCreated,
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
        uint256 vSignalCreated
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
        uint256 tokensExchanged,
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
     * @param _didRegistry Address of the Ethereum DID registry
     * @param _curation Address of the Curation contract
     * @param _token Address of the Graph Token contract
     */
    constructor(
        address _didRegistry,
        address _curation,
        address _token
    ) public {
        Governed._initialize(msg.sender);
        erc1056Registry = IEthereumDIDRegistry(_didRegistry);
        curation = ICuration(_curation);
        token = IGraphToken(_token);
        token.approve(_curation, uint256(-1));
    }

    /**
     * @dev Set the minimum vSignal to be staked to create nSignal
     * @notice Update the minimum vSignal amount to `_minimumVSignalStake`
     * @param _minimumVSignalStake Minimum amount of vSignal required
     */
    function setMinimumVsignal(uint256 _minimumVSignalStake) external onlyGovernor {
        require(_minimumVSignalStake > 0, "Minimum vSignal cannot be 0");
        minimumVSignalStake = _minimumVSignalStake;
        emit ParameterUpdated("minimumVSignalStake");
    }

    function setDefaultName(
        address _graphAccount,
        uint8 _nameSystem,
        bytes32 _nameIdentifier,
        string calldata _name
    ) external onlyGraphAccountOwner(_graphAccount) {
        emit SetDefaultName(_graphAccount, _nameSystem, _nameIdentifier, _name);
    }

    function updateSubgraphMetadata(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _metadataHash
    ) public onlyGraphAccountOwner(_graphAccount) {
        emit SubgraphMetadataUpdated(_graphAccount, _subgraphNumber, _metadataHash);
    }

    /**
     * @dev Allows a graph account to publish a new subgraph, which means a new subgraph number
     * will be used.
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _versionMetadata IPFS hash for the subgraph version metadata
     */
    function publishNewSubgraph(
        address _graphAccount,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) external onlyGraphAccountOwner(_graphAccount) {
        uint256 subgraphNumber = graphAccountSubgraphNumbers[_graphAccount];
        publishVersion(_graphAccount, subgraphNumber, _subgraphDeploymentID, _versionMetadata);
        graphAccountSubgraphNumbers[_graphAccount]++;
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
    ) external onlyGraphAccountOwner(_graphAccount) {
        require(
            isPublished(_graphAccount, _subgraphNumber),
            "GNS: Cannot update version if not published, or has been deprecated"
        );
        publishVersion(_graphAccount, _subgraphNumber, _subgraphDeploymentID, _versionMetadata);
    }

    /**
     * @dev Internal function used by both external publishing functions
     * @param _graphAccount Account that is publishing the subgraph
     * @param _subgraphNumber Subgraph number for the account
     * @param _subgraphDeploymentID Subgraph deployment ID of the version, linked to the name
     * @param _versionMetadata IPFS hash for the subgraph version metadata
     */
    function publishVersion(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _subgraphDeploymentID,
        bytes32 _versionMetadata
    ) internal {
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
        onlyGraphAccountOwner(_graphAccount)
    {
        require(
            isPublished(_graphAccount, _subgraphNumber),
            "GNS: Cannot deprecate a subgraph which does not exist"
        );
        delete subgraphs[_graphAccount][_subgraphNumber];
        emit SubgraphDeprecated(_graphAccount, _subgraphNumber);
    }

    /**
     * @dev Enable name signal on a graph accounts numbered subgraph, which points to a subgraph
     * deployment
     * @param _graphAccount Graph account enabling name signal
     * @param _subgraphNumber Subgraph number being used
     * @param _graphTokens Graph tokens deposited to initialze the curve
     */
    function enableNameSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        uint256 _graphTokens
    ) external onlyGraphAccountOwner(_graphAccount) {
        // Checks
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(
            namePool.reserveRatio == 0,
            "GNS: Enable name signal was already called for this subgraph number"
        );
        bytes32 subgraphDeploymentID = subgraphs[_graphAccount][_subgraphNumber];
        require(
            subgraphDeploymentID != 0,
            "GNS: Cannot enable name signal on a subgraph without a deployment ID"
        );

        namePool.reserveRatio = defaultReserveRatio;
        namePool.subgraphDeploymentID = subgraphDeploymentID;

        // Update values
        (uint256 vSignal, uint256 nSignal) = _mintNSignal(
            _graphAccount,
            _subgraphNumber,
            _graphTokens
        );
        emit NameSignalEnabled(
            _graphAccount,
            _subgraphNumber,
            vSignal,
            nSignal,
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
    function upgradeNameSignal(
        address _graphAccount,
        uint256 _subgraphNumber,
        bytes32 _newSubgraphDeploymentID
    ) external onlyGraphAccountOwner(_graphAccount) {
        require(_newSubgraphDeploymentID != 0, "GNS: Deployment ID cannot be 0");
        bytes32 subgraphDeploymentID = subgraphs[_graphAccount][_subgraphNumber];
        // Subgraph owner must first update the numbered subgraph to point to this deploymentID
        // Then they can direct the name curators vSignal to this new name curation curve
        require(
            _newSubgraphDeploymentID == subgraphDeploymentID,
            "GNS: Owner did not update subgraph deployment ID"
        );

        // This is to prevent the owner from front running their name curators signal by posting
        // their own signal ahead, bringing the name curators in, and dumping on them
        require(
            !curation.isCurated(_newSubgraphDeploymentID),
            "GNS: Owner cannot point to a subgraphID that has been pre-curated"
        );

        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(
            _newSubgraphDeploymentID != namePool.subgraphDeploymentID,
            "GNS: Cannot upgrade to the exact same subgraph deployment ID"
        );
        require(
            namePool.nSignal > 0,
            "GNS: There must be nSignal on this subgraph for curve math to work"
        );
        require(namePool.disabled == false, "GNS: Cannot be disabled");

        uint256 vSignalOld = nSignalToVSignal(_graphAccount, _subgraphNumber, namePool.nSignal);
        (uint256 tokens, uint256 withdrawalFees) = _burnVSignal(
            _graphAccount,
            namePool.subgraphDeploymentID,
            vSignalOld
        );
        namePool.vSignal = namePool.vSignal.sub(vSignalOld);
        // Update name signals deployment ID to match the subgraphs deployment ID
        namePool.subgraphDeploymentID = subgraphDeploymentID;

        // nSignal stays constant, but vSignal can change here
        uint256 vSignalNew = curation.mint(
            namePool.subgraphDeploymentID,
            (tokens + withdrawalFees)
        );
        namePool.vSignal = vSignalNew;
        emit NameSignalUpgrade(
            _graphAccount,
            _subgraphNumber,
            vSignalNew,
            tokens + withdrawalFees,
            subgraphDeploymentID
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
    ) external {
        address nameCurator = msg.sender;
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(namePool.disabled == false, "GNS: Cannot be disabled");
        require(
            namePool.subgraphDeploymentID != 0,
            "GNS: Must deposit on a name signal that exists"
        );

        bytes32 subgraphDeploymentID = subgraphs[_graphAccount][_subgraphNumber];

        // This happens when the owner updates the deploymentID, but has not yet updated the
        // name signal to point here. Preventing users from staking on name
        // NOTE - might be possible to combine this into one function, but lots of rework
        require(
            namePool.subgraphDeploymentID == subgraphDeploymentID,
            "GNS: Name owner updated version without updating name signal"
        );

        (uint256 vSignal, uint256 nSignal) = _mintNSignal(_graphAccount, _subgraphNumber, _tokens);
        emit NSignalMinted(_graphAccount, _subgraphNumber, msg.sender, nSignal, vSignal);
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
    ) external {
        address nameCurator = msg.sender;
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 curatorNSignal = namePool.curatorNSignal[nameCurator];
        require(namePool.disabled == false, "GNS: Cannot be disabled");
        bytes32 subgraphDeploymentID = subgraphs[_graphAccount][_subgraphNumber];

        // This happens when the owner updates the deploymentID, but has not yet updated the
        // name signal to point here. Preventing users from staking on name
        // NOTE - might be possible to combine this into one function, but lots of rework
        require(
            namePool.subgraphDeploymentID == subgraphDeploymentID,
            "GNS: Name owner updated version without updating name signal"
        );
        require(
            _nSignal <= curatorNSignal,
            "GNS: Curator cannot withdraw more nSignal than they have"
        );

        (uint256 vSignal, uint256 tokens) = _burnNSignal(_graphAccount, _subgraphNumber, _nSignal);
        // Return the tokens to the nameCurator
        require(token.transfer(nameCurator, tokens), "GNS: Error sending nameCurators tokens");
        emit NSignalBurned(_graphAccount, _subgraphNumber, msg.sender, _nSignal, vSignal, tokens);
    }

    /**
     * @dev Owner disables the subgraph. This means the subgraph-number combination can no longer
     * be used for name signal. The nSignal curve is destroyed, the vSignal is burned, and the GNS
     * contract holds the GRT from burning the vSignal, which all curators can withdraw manually.
     * @param _graphAccount Account that is deprecating their name curation
     * @param _subgraphNumber Subgraph number
     */
    function disableNameSignal(address _graphAccount, uint256 _subgraphNumber)
        external
        onlyGraphAccountOwner(_graphAccount)
    {
        bytes32 subgraphDeploymentID = subgraphs[_graphAccount][_subgraphNumber];
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(
            namePool.subgraphDeploymentID == subgraphDeploymentID, // TODO EDGE CASE - when both subgraph ids are 0, this will fail, leading something to be deprecated before it exists
            "GNS: Name owner updated version without updating name signal"
        );
        require(namePool.disabled == false, "GNS: Cannot be disabled twice");
        uint256 vSignal = namePool.vSignal;
        namePool.vSignal = 0;
        (uint256 tokens, uint256 withdrawalFees) = curation.burn(subgraphDeploymentID, vSignal);

        // Get the owner of the Name to reimburse the withdrawal fee
        require(
            token.transferFrom(_graphAccount, address(this), withdrawalFees),
            "GNS: Error reimbursing withdrawal fees"
        );

        // Set the NameCurationPool fields to make it disabled
        namePool.disabled = true;
        namePool.withdrawableGRT = tokens + withdrawalFees;
        emit NameSignalDisabled(_graphAccount, _subgraphNumber, namePool.withdrawableGRT);
    }

    /**
     * @dev When the subgraph curve is disabled, all nameCurators can call this function and
     * withdraw the GRT they are entitled for their original deposit of vSignal
     * @param _graphAccount Subgraph owner
     * @param _subgraphNumber Subgraph owners subgraph number which was curated on by nameCurators
     */
    function withdraw(address _graphAccount, uint256 _subgraphNumber) external {
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
            token.transfer(msg.sender, tokens),
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
            token.transferFrom(msg.sender, address(this), _tokens),
            "GNS: Cannot transfer tokens to stake"
        );
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = curation.mint(namePool.subgraphDeploymentID, _tokens);
        uint256 nSignal = vSignalToNSignal(_graphAccount, _subgraphNumber, vSignal);
        namePool.vSignal = namePool.vSignal.add(vSignal);
        namePool.nSignal = namePool.nSignal.add(nSignal);
        namePool.curatorNSignal[msg.sender] = namePool.curatorNSignal[msg.sender].add(nSignal);
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
        NameCurationPool storage namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = nSignalToVSignal(_graphAccount, _subgraphNumber, _nSignal);
        (uint256 tokens, ) = curation.burn(namePool.subgraphDeploymentID, vSignal);
        namePool.vSignal = namePool.vSignal.sub(vSignal);
        namePool.nSignal = namePool.nSignal.sub(_nSignal);
        namePool.curatorNSignal[msg.sender] = namePool.curatorNSignal[msg.sender].sub(_nSignal);
        return (vSignal, tokens);
    }

    /**
     * @dev Calculations burning vSignal from disabled or upgrade, while keeping n signal constant.
     * Takes the withdrawal fee from the name owner so they cannot grief all the name curators
     * @param _graphAccount Subgraph owner
     * @param _subgraphDeploymentID Subgraph deployment to burn all vSignal from
     * @param _vSignal vSignal being burnt
     * @return Tokens returned to the gns contract, and withdrawal fees the owner transferred to the gns
     */
    function _burnVSignal(
        address _graphAccount,
        bytes32 _subgraphDeploymentID,
        uint256 _vSignal
    ) private returns (uint256, uint256) {
        (uint256 tokens, uint256 withdrawalFees) = curation.burn(_subgraphDeploymentID, _vSignal);
        require(
            token.transferFrom(_graphAccount, address(this), withdrawalFees),
            "GNS: Error reimbursing withdrawal fees"
        );
        return (tokens, withdrawalFees);
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
    ) public view returns (uint256, uint256) {
        NameCurationPool memory namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = curation.tokensToSignal(namePool.subgraphDeploymentID, _tokens);
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
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        NameCurationPool memory namePool = nameSignals[_graphAccount][_subgraphNumber];
        uint256 vSignal = nSignalToVSignal(_graphAccount, _subgraphNumber, _nSignal);
        (uint256 tokens, uint256 withdrawalFees) = curation.signalToTokens(
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
    ) public view returns (uint256) {
        NameCurationPool memory namePool = nameSignals[_graphAccount][_subgraphNumber];
        require(
            namePool.disabled == false,
            "GNS: Name cannot be disabled to call vSignalToNSignal()"
        );
        uint256 vSignal = _vSignal;
        uint256 nSignalInit = 0;
        uint32 reserveRatio = namePool.reserveRatio;
        // Handle initialization of bonding curve
        if (namePool.vSignal == 0) {
            namePool.vSignal = minimumVSignalStake;
            vSignal = vSignal.sub(namePool.vSignal);
            namePool.nSignal = VSIGNAL_PER_MINIMUM_NSIGNAL;
            nSignalInit = namePool.nSignal;
            reserveRatio = defaultReserveRatio;
        }

        return
            calculatePurchaseReturn(
                namePool.nSignal,
                namePool.vSignal,
                reserveRatio,
                vSignal // deposit the vSignal into the nSignal bonding curve
            ) + nSignalInit;
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
    ) public view returns (uint256) {
        NameCurationPool memory namePool = nameSignals[_graphAccount][_subgraphNumber];
        return
            calculateSaleReturn(
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
    ) public view returns (uint256) {
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
        returns (bool)
    {
        return subgraphs[_graphAccount][_subgraphNumber] != 0;
    }
}
