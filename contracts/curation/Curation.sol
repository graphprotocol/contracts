pragma solidity ^0.6.4;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../governance/Governed.sol";
import "../upgrades/GraphProxy.sol";

import "./CurationStorage.sol";
import "./ICuration.sol";

/**
 * @title Curation contract
 * @dev Allows curators to signal on subgraph deployments that might be relevant to indexers by
 * staking Graph Tokens (GRT). Additionally, curators earn fees from the Query Market related to the
 * subgraph deployment they curate.
 * A curators stake goes to a curation pool along with the stakes of other curators,
 * only one such pool exists for each subgraph deployment.
 * The contract mints Graph Signal Tokens (GST) according to a bonding curve for each individual
 * curation pool where GRT is deposited.
 * Holders can burn GST tokens using this contract to get GRT tokens back according to the
 * bonding curve.
 */
contract Curation is CurationV1Storage, ICuration, Governed {
    using SafeMath for uint256;

    // 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;

    // Amount of signal you get with your minimum token stake
    uint256 private constant SIGNAL_PER_MINIMUM_STAKE = 1 ether;

    // -- Events --

    /**
     * @dev Emitted when `curator` staked `tokens` on `subgraphDeploymentID` as curation signal.
     * The `curator` receives `signal` amount according to the curation pool bonding curve.
     */
    event Signalled(
        address indexed curator,
        bytes32 indexed subgraphDeploymentID,
        uint256 tokens,
        uint256 signal
    );

    /**
     * @dev Emitted when `curator` burned `signal` for a `subgraphDeploymentID`.
     * The curator will receive `tokens` according to the value of the bonding curve.
     * An amount of `withdrawalFees` will be collected and burned.
     */
    event Burned(
        address indexed curator,
        bytes32 indexed subgraphDeploymentID,
        uint256 tokens,
        uint256 signal,
        uint256 withdrawalFees
    );

    /**
     * @dev Emitted when `tokens` amount were collected for `subgraphDeploymentID` as part of fees
     * distributed by an indexer from the settlement of query fees.
     */
    event Collected(bytes32 indexed subgraphDeploymentID, uint256 tokens);

    /**
     * @dev Check if the caller is the governor or initializing the implementation.
     */
    modifier onlyGovernorOrInit {
        require(msg.sender == governor || msg.sender == implementation, "Only Governor can call");
        _;
    }

    /**
     * @dev Initialize this contract.
     */
    function initialize(
        address _token,
        uint32 _defaultReserveRatio,
        uint256 _minimumCurationStake
    ) external onlyGovernorOrInit {
        BancorFormula._initialize();
        token = IGraphToken(_token);
        defaultReserveRatio = _defaultReserveRatio;
        minimumCurationStake = _minimumCurationStake;
    }

    /**
     * @dev Accept to be an implementation of proxy and run initializer.
     * @param _proxy Graph proxy delegate caller
     * @param _token Address of the Graph Protocol token
     * @param _defaultReserveRatio Reserve ratio to initialize the bonding curve of CurationPool
     * @param _minimumCurationStake Minimum amount of tokens that curators can stake
     */
    function acceptProxy(
        GraphProxy _proxy,
        address _token,
        uint32 _defaultReserveRatio,
        uint256 _minimumCurationStake
    ) external {
        require(msg.sender == _proxy.governor(), "Only proxy governor can upgrade");

        // Accept to be the implementation for this proxy
        _proxy.acceptImplementation();

        // Initialization
        Curation(address(_proxy)).initialize(_token, _defaultReserveRatio, _minimumCurationStake);
    }

    /**
     * @dev Set the staking contract used for fees distribution.
     * @notice Update the staking contract to `_staking`
     * @param _staking Address of the staking contract
     */
    function setStaking(address _staking) external override onlyGovernorOrInit {
        staking = IStaking(_staking);
        emit ParameterUpdated("staking");
    }

    /**
     * @dev Set the default reserve ratio percentage for a curation pool.
     * @notice Update the default reserver ratio to `_defaultReserveRatio`
     * @param _defaultReserveRatio Reserve ratio (in PPM)
     */
    function setDefaultReserveRatio(uint32 _defaultReserveRatio)
        external
        override
        onlyGovernorOrInit
    {
        // Reserve Ratio must be within 0% to 100% (exclusive, in PPM)
        require(_defaultReserveRatio > 0, "Default reserve ratio must be > 0");
        require(
            _defaultReserveRatio <= MAX_PPM,
            "Default reserve ratio cannot be higher than MAX_PPM"
        );

        defaultReserveRatio = _defaultReserveRatio;
        emit ParameterUpdated("defaultReserveRatio");
    }

    /**
     * @dev Set the minimum stake amount for curators.
     * @notice Update the minimum stake amount to `_minimumCurationStake`
     * @param _minimumCurationStake Minimum amount of tokens required stake
     */
    function setMinimumCurationStake(uint256 _minimumCurationStake)
        external
        override
        onlyGovernorOrInit
    {
        require(_minimumCurationStake > 0, "Minimum curation stake cannot be 0");
        minimumCurationStake = _minimumCurationStake;
        emit ParameterUpdated("minimumCurationStake");
    }

    /**
     * @dev Set the fee percentage to charge when a curator withdraws stake.
     * @param _percentage Percentage fee charged when withdrawing stake
     */
    function setWithdrawalFeePercentage(uint32 _percentage) external override onlyGovernorOrInit {
        // Must be within 0% to 100% (inclusive)
        require(
            _percentage <= MAX_PPM,
            "Withdrawal fee percentage must be below or equal to MAX_PPM"
        );
        withdrawalFeePercentage = _percentage;
        emit ParameterUpdated("withdrawalFeePercentage");
    }

    /**
     * @dev Assign Graph Tokens collected as curation fees to the curation pool reserve.
     * @param _subgraphDeploymentID SubgraphDeployment where funds should be allocated as reserves
     * @param _tokens Amount of Graph Tokens to add to reserves
     */
    function collect(bytes32 _subgraphDeploymentID, uint256 _tokens) external override {
        require(msg.sender == address(staking), "Caller must be the staking contract");

        // Transfer tokens collected from the staking contract to this contract
        require(
            token.transferFrom(address(staking), address(this), _tokens),
            "Cannot transfer tokens to collect"
        );

        // Collect tokens and assign them to the reserves
        _collect(_subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Stake Graph Tokens in exchange for signal of a SubgraphDeployment curation pool.
     * @param _subgraphDeploymentID Subgraph deployment pool from where to mint signal
     * @param _tokens Amount of Graph Tokens to stake
     */
    function mint(bytes32 _subgraphDeploymentID, uint256 _tokens) external override {
        address curator = msg.sender;

        // Need to stake some funds
        require(_tokens > 0, "Cannot stake zero tokens");

        // Transfer tokens from the curator to this contract
        require(
            token.transferFrom(curator, address(this), _tokens),
            "Cannot transfer tokens to stake"
        );

        // Stake tokens to a curation pool reserve
        _mint(curator, _subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Return an amount of signal to get tokens back.
     * @notice Burn _signal from the SubgraphDeployment curation pool
     * @param _subgraphDeploymentID SubgraphDeployment the curator is returning signal
     * @param _signal Amount of signal to return
     */
    function burn(bytes32 _subgraphDeploymentID, uint256 _signal) external override {
        address curator = msg.sender;

        require(_signal > 0, "Cannot burn zero signal");
        require(
            getCuratorSignal(curator, _subgraphDeploymentID) >= _signal,
            "Cannot burn more signal than you own"
        );

        // Update balance and get the amount of tokens to refund based on returned signal
        uint256 tokens = _burnSignal(curator, _subgraphDeploymentID, _signal);

        // If all signal burnt delete the curation pool
        if (getCurationPoolSignal(_subgraphDeploymentID) == 0) {
            delete pools[_subgraphDeploymentID];
        }

        // Calculate withdrawal fees and burn the tokens
        uint256 withdrawalFees = uint256(withdrawalFeePercentage).mul(tokens).div(MAX_PPM);
        if (withdrawalFees > 0) {
            tokens = tokens.sub(withdrawalFees);
            token.burn(withdrawalFees);
        }

        // Return the tokens to the curator
        require(token.transfer(curator, tokens), "Error sending curator tokens");

        emit Burned(curator, _subgraphDeploymentID, tokens, _signal, withdrawalFees);
    }

    /**
     * @dev Check if any Graph tokens are staked for a SubgraphDeployment.
     * @param _subgraphDeploymentID SubgraphDeployment to check if curated
     * @return True if curated
     */
    function isCurated(bytes32 _subgraphDeploymentID) public override view returns (bool) {
        return pools[_subgraphDeploymentID].tokens > 0;
    }

    /**
     * @dev Get the amount of signal a curator has in a curation pool.
     * @param _curator Curator owning the signal tokens
     * @param _subgraphDeploymentID Subgraph deployment curation pool
     * @return Amount of signal owned by a curator for the subgraph deployment
     */
    function getCuratorSignal(address _curator, bytes32 _subgraphDeploymentID)
        public
        override
        view
        returns (uint256)
    {
        if (address(pools[_subgraphDeploymentID].gst) == address(0)) {
            return 0;
        }
        return pools[_subgraphDeploymentID].gst.balanceOf(_curator);
    }

    /**
     * @dev Get the amount of signal in a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment curation poool
     * @return Amount of signal owned by a curator for the subgraph deployment
     */
    function getCurationPoolSignal(bytes32 _subgraphDeploymentID)
        public
        override
        view
        returns (uint256)
    {
        if (address(pools[_subgraphDeploymentID].gst) == address(0)) {
            return 0;
        }
        return pools[_subgraphDeploymentID].gst.totalSupply();
    }

    /**
     * @dev Calculate amount of signal that can be bought with tokens in a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment to mint signal
     * @param _tokens Amount of tokens used to mint signal
     * @return Amount of signal that can be bought
     */
    function tokensToSignal(bytes32 _subgraphDeploymentID, uint256 _tokens)
        public
        override
        view
        returns (uint256)
    {
        // Get current tokens and signal
        CurationPool memory curationPool = pools[_subgraphDeploymentID];
        uint256 newTokens = _tokens;
        uint256 curTokens = curationPool.tokens;
        uint256 curSignal = getCurationPoolSignal(_subgraphDeploymentID);
        uint32 reserveRatio = curationPool.reserveRatio;

        // Init curation pool
        if (curationPool.tokens == 0) {
            newTokens = newTokens.sub(minimumCurationStake);
            curTokens = minimumCurationStake;
            curSignal = SIGNAL_PER_MINIMUM_STAKE;
            reserveRatio = defaultReserveRatio;
        }

        // Calculate new signal
        uint256 newSignal = calculatePurchaseReturn(curSignal, curTokens, reserveRatio, newTokens);
        return newSignal.add(curSignal);
    }

    /**
     * @dev Calculate number of tokens to get when burning signal from a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment to burn signal
     * @param _signal Amount of signal to burn
     * @return Amount of tokens to get after burning signal
     */
    function signalToTokens(bytes32 _subgraphDeploymentID, uint256 _signal)
        public
        override
        view
        returns (uint256)
    {
        CurationPool memory curationPool = pools[_subgraphDeploymentID];
        uint256 curationPoolSignal = getCurationPoolSignal(_subgraphDeploymentID);
        require(
            curationPool.tokens > 0,
            "Subgraph deployment must be curated to perform calculations"
        );
        require(
            curationPoolSignal >= _signal,
            "Signal must be above or equal to signal issued in the curation pool"
        );
        return
            calculateSaleReturn(
                curationPoolSignal,
                curationPool.tokens,
                uint32(curationPool.reserveRatio),
                _signal
            );
    }

    /**
     * @dev Update balances after mint of signal and deposit of tokens.
     * @param _curator Curator address
     * @param _subgraphDeploymentID Subgraph deployment from where to mint signal
     * @param _tokens Amount of tokens to deposit
     * @return Amount of signal minted
     */
    function _mintSignal(
        address _curator,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens
    ) private returns (uint256) {
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        uint256 signal = tokensToSignal(_subgraphDeploymentID, _tokens);

        // Update GRT tokens held as reserves
        curationPool.tokens = curationPool.tokens.add(_tokens);

        // Mint signal to the curator
        curationPool.gst.mint(_curator, signal);

        return signal;
    }

    /**
     * @dev Update balances after burn of signal and return of tokens.
     * @param _curator Curator address
     * @param _subgraphDeploymentID Subgraph deployment pool to burn signal
     * @param _signal Amount of signal to burn
     * @return Number of tokens received
     */
    function _burnSignal(
        address _curator,
        bytes32 _subgraphDeploymentID,
        uint256 _signal
    ) private returns (uint256) {
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        uint256 tokens = signalToTokens(_subgraphDeploymentID, _signal);

        // Update GRT tokens held as reserves
        curationPool.tokens = curationPool.tokens.sub(tokens);

        // Burn signal from curator
        curationPool.gst.burnFrom(_curator, _signal);

        return tokens;
    }

    /**
     * @dev Assign Graph Tokens received from staking to the curation pool reserve.
     * @param _subgraphDeploymentID Subgraph deployment where funds should be allocated as reserves
     * @param _tokens Amount of Graph Tokens to add to reserves
     */
    function _collect(bytes32 _subgraphDeploymentID, uint256 _tokens) private {
        require(
            isCurated(_subgraphDeploymentID),
            "Subgraph deployment must be curated to collect fees"
        );

        // Collect new funds into reserve
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        curationPool.tokens = curationPool.tokens.add(_tokens);

        emit Collected(_subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Deposit Graph Tokens in exchange for signal of a curation pool.
     * @param _curator Address of the staking party
     * @param _subgraphDeploymentID Subgraph deployment from where the curator is minting
     * @param _tokens Amount of Graph Tokens to stake
     */
    function _mint(
        address _curator,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens
    ) private {
        CurationPool storage curationPool = pools[_subgraphDeploymentID];

        // If it hasn't been curated before then initialize the curve
        if (!isCurated(_subgraphDeploymentID)) {
            require(_tokens >= minimumCurationStake, "Curation stake is below minimum required");

            // Initialize
            curationPool.reserveRatio = defaultReserveRatio;

            // If no signal token for the pool - create one
            if (address(curationPool.gst) == address(0)) {
                string memory symbol = string(abi.encodePacked("GST-", _subgraphDeploymentID));
                curationPool.gst = new GraphSignalToken(symbol, address(this));
            }
        }

        // Update balances
        uint256 signal = _mintSignal(_curator, _subgraphDeploymentID, _tokens);

        emit Signalled(_curator, _subgraphDeploymentID, _tokens, signal);
    }
}
