pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../bancor/BancorFormula.sol";
import "../upgrades/GraphUpgradeable.sol";

import "./CurationStorage.sol";
import "./ICuration.sol";
import "./GraphSignalToken.sol";

/**
 * @title Curation contract
 * @dev Allows curators to signal on subgraph deployments that might be relevant to indexers by
 * staking Graph Tokens (GRT). Additionally, curators earn fees from the Query Market related to the
 * subgraph deployment they curate.
 * A curators deposit goes to a curation pool along with the deposits of other curators,
 * only one such pool exists for each subgraph deployment.
 * The contract mints Graph Signal Tokens (GST) according to a bonding curve for each individual
 * curation pool where GRT is deposited.
 * Holders can burn GST tokens using this contract to get GRT tokens back according to the
 * bonding curve.
 */
contract Curation is CurationV1Storage, GraphUpgradeable, ICuration {
    using SafeMath for uint256;

    // 100% in parts per million
    uint32 private constant MAX_PPM = 1000000;

    // Amount of signal you get with your minimum token deposit
    uint256 private constant SIGNAL_PER_MINIMUM_DEPOSIT = 1e18; // 1 signal as 18 decimal number

    // -- Events --

    /**
     * @dev Emitted when `curator` deposited `tokens` on `subgraphDeploymentID` as curation signal.
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
     * @dev Initialize this contract.
     */
    function initialize(
        address _controller,
        address _bondingCurve,
        uint32 _defaultReserveRatio,
        uint256 _minimumCurationDeposit
    ) external onlyImpl {
        Managed._initialize(_controller);

        bondingCurve = _bondingCurve;
        defaultReserveRatio = _defaultReserveRatio;
        minimumCurationDeposit = _minimumCurationDeposit;
    }

    /**
     * @dev Accept to be an implementation of proxy and run initializer.
     * @param _proxy Graph proxy delegate caller
     * @param _controller Controller for this contract
     * @param _defaultReserveRatio Reserve ratio to initialize the bonding curve of CurationPool
     * @param _minimumCurationDeposit Minimum amount of tokens that curators can deposit
     */
    function acceptProxy(
        IGraphProxy _proxy,
        address _controller,
        address _bondingCurve,
        uint32 _defaultReserveRatio,
        uint256 _minimumCurationDeposit
    ) external {
        // Accept to be the implementation for this proxy
        _acceptUpgrade(_proxy);

        // Initialization
        Curation(address(_proxy)).initialize(
            _controller,
            _bondingCurve,
            _defaultReserveRatio,
            _minimumCurationDeposit
        );
    }

    /**
     * @dev Set the default reserve ratio percentage for a curation pool.
     * @notice Update the default reserver ratio to `_defaultReserveRatio`
     * @param _defaultReserveRatio Reserve ratio (in PPM)
     */
    function setDefaultReserveRatio(uint32 _defaultReserveRatio) external override onlyGovernor {
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
     * @dev Set the minimum deposit amount for curators.
     * @notice Update the minimum deposit amount to `_minimumCurationDeposit`
     * @param _minimumCurationDeposit Minimum amount of tokens required deposit
     */
    function setMinimumCurationDeposit(uint256 _minimumCurationDeposit)
        external
        override
        onlyGovernor
    {
        require(_minimumCurationDeposit > 0, "Minimum curation deposit cannot be 0");
        minimumCurationDeposit = _minimumCurationDeposit;
        emit ParameterUpdated("minimumCurationDeposit");
    }

    /**
     * @dev Set the fee percentage to charge when a curator withdraws GRT tokens.
     * @param _percentage Percentage fee charged when withdrawing GRT tokens
     */
    function setWithdrawalFeePercentage(uint32 _percentage) external override onlyGovernor {
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
    function collect(bytes32 _subgraphDeploymentID, uint256 _tokens) external override onlyStaking {
        // Transfer tokens collected from the staking contract to this contract
        require(
            graphToken().transferFrom(address(staking()), address(this), _tokens),
            "Cannot transfer tokens to collect"
        );

        // Collect tokens and assign them to the reserves
        _collect(_subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Deposit Graph Tokens in exchange for signal of a SubgraphDeployment curation pool.
     * @param _subgraphDeploymentID Subgraph deployment pool from where to mint signal
     * @param _tokens Amount of Graph Tokens to deposit
     * @return Signal minted
     */
    function mint(bytes32 _subgraphDeploymentID, uint256 _tokens)
        external
        override
        notRecoveryPaused
        returns (uint256)
    {
        address curator = msg.sender;

        // Need to deposit some funds
        require(_tokens > 0, "Cannot deposit zero tokens");

        // Transfer tokens from the curator to this contract
        require(
            graphToken().transferFrom(curator, address(this), _tokens),
            "Cannot transfer tokens to deposit"
        );

        // Deposit tokens to a curation pool reserve
        return _mint(curator, _subgraphDeploymentID, _tokens);
    }

    /**
     * @dev Return an amount of signal to get tokens back.
     * @notice Burn _signal from the SubgraphDeployment curation pool
     * @param _subgraphDeploymentID SubgraphDeployment the curator is returning signal
     * @param _signal Amount of signal to return
     * @return Tokens returned and withdrawal fees
     */
    function burn(bytes32 _subgraphDeploymentID, uint256 _signal)
        external
        override
        notRecoveryPaused
        returns (uint256, uint256)
    {
        address curator = msg.sender;

        require(_signal > 0, "Cannot burn zero signal");
        require(
            getCuratorSignal(curator, _subgraphDeploymentID) >= _signal,
            "Cannot burn more signal than you own"
        );

        // Trigger update rewards calculation
        _updateRewards(_subgraphDeploymentID);

        // Update balance and get the amount of tokens to refund based on returned signal
        (uint256 tokens, uint256 withdrawalFees) = _burnSignal(
            curator,
            _subgraphDeploymentID,
            _signal
        );

        // If all signal burnt delete the curation pool
        if (getCurationPoolSignal(_subgraphDeploymentID) == 0) {
            delete pools[_subgraphDeploymentID];
        }

        IGraphToken graphToken = graphToken();
        // Burn withdrawal fees
        if (withdrawalFees > 0) {
            graphToken.burn(withdrawalFees);
        }

        // Return the tokens to the curator
        require(graphToken.transfer(curator, tokens), "Error sending curator tokens");

        emit Burned(curator, _subgraphDeploymentID, tokens, _signal, withdrawalFees);
        return (tokens, withdrawalFees);
    }

    /**
     * @dev Check if any GRT tokens are deposited for a SubgraphDeployment.
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
     * @return Amount of signal minted for the subgraph deployment
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
     * @dev Get the amount of token reserves in a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment curation poool
     * @return Amount of token reserves in the curation pool
     */
    function getCurationPoolTokens(bytes32 _subgraphDeploymentID)
        public
        override
        view
        returns (uint256)
    {
        return pools[_subgraphDeploymentID].tokens;
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
            require(
                newTokens >= minimumCurationDeposit,
                "Tokens cannot be under minimum curation deposit when curve not initialized"
            );
            newTokens = newTokens.sub(minimumCurationDeposit);
            curTokens = minimumCurationDeposit;
            curSignal = SIGNAL_PER_MINIMUM_DEPOSIT;
            reserveRatio = defaultReserveRatio;
        }

        // Calculate new signal
        uint256 newSignal = BancorFormula(bondingCurve).calculatePurchaseReturn(
            curSignal,
            curTokens,
            reserveRatio,
            newTokens
        );
        return newSignal.add(curSignal);
    }

    /**
     * @dev Calculate number of tokens to get when burning signal from a curation pool.
     * @param _subgraphDeploymentID Subgraph deployment to burn signal
     * @param _signal Amount of signal to burn
     * @return Amount of tokens to get after burning signal and withdrawal fees
     */
    function signalToTokens(bytes32 _subgraphDeploymentID, uint256 _signal)
        public
        override
        view
        returns (uint256, uint256)
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

        uint256 tokens = BancorFormula(bondingCurve).calculateSaleReturn(
            curationPoolSignal,
            curationPool.tokens,
            curationPool.reserveRatio,
            _signal
        );
        uint256 withdrawalFees = tokens.mul(uint256(withdrawalFeePercentage)).div(MAX_PPM);

        return (tokens.sub(withdrawalFees), withdrawalFees);
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
    ) internal returns (uint256) {
        uint256 signal = tokensToSignal(_subgraphDeploymentID, _tokens);

        // Update curation pool
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        // Update GRT tokens held as reserves
        curationPool.tokens = curationPool.tokens.add(_tokens);
        // Mint signal to the curator
        curationPool.gst.mint(_curator, signal);

        // Update the global reserve
        totalTokens = totalTokens.add(_tokens);

        return signal;
    }

    /**
     * @dev Update balances after burn of signal and return of tokens.
     * @param _curator Curator address
     * @param _subgraphDeploymentID Subgraph deployment pool to burn signal
     * @param _signal Amount of signal to burn
     * @return Number of tokens received and withdrawal fees
     */
    function _burnSignal(
        address _curator,
        bytes32 _subgraphDeploymentID,
        uint256 _signal
    ) internal returns (uint256, uint256) {
        (uint256 tokens, uint256 withdrawalFees) = signalToTokens(_subgraphDeploymentID, _signal);
        uint256 outTokens = tokens.add(withdrawalFees);

        // Update curation pool
        CurationPool storage curationPool = pools[_subgraphDeploymentID];
        // Update GRT tokens held as reserves
        curationPool.tokens = curationPool.tokens.sub(outTokens);
        // Burn signal from curator
        curationPool.gst.burnFrom(_curator, _signal);

        // Update the global reserve
        totalTokens = totalTokens.sub(outTokens);

        return (tokens, withdrawalFees);
    }

    /**
     * @dev Assign Graph Tokens received from staking to the curation pool reserve.
     * @param _subgraphDeploymentID Subgraph deployment where funds should be allocated as reserves
     * @param _tokens Amount of Graph Tokens to add to reserves
     */
    function _collect(bytes32 _subgraphDeploymentID, uint256 _tokens) internal {
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
     * @param _tokens Amount of Graph Tokens to deposit
     * @return Signal minted
     */
    function _mint(
        address _curator,
        bytes32 _subgraphDeploymentID,
        uint256 _tokens
    ) internal returns (uint256) {
        CurationPool storage curationPool = pools[_subgraphDeploymentID];

        // If it hasn't been curated before then initialize the curve
        if (!isCurated(_subgraphDeploymentID)) {
            require(
                _tokens >= minimumCurationDeposit,
                "Curation deposit is below minimum required"
            );

            // Initialize
            curationPool.reserveRatio = defaultReserveRatio;

            // If no signal token for the pool - create one
            if (address(curationPool.gst) == address(0)) {
                // TODO: the gas cost of deploying the subgraph token can be greatly optimized
                // by deploying a proxy each time, sharing the same implementation
                curationPool.gst = IGraphSignalToken(
                    address(new GraphSignalToken("GST", address(this)))
                );
            }
        }

        // Trigger update rewards calculation
        _updateRewards(_subgraphDeploymentID);

        // Exchange GRT tokens for GST of the subgraph pool
        uint256 signal = _mintSignal(_curator, _subgraphDeploymentID, _tokens);

        emit Signalled(_curator, _subgraphDeploymentID, _tokens, signal);
        return signal;
    }

    /**
     * @dev Triggers an update of rewards due to a change in signal.
     * @param _subgraphDeploymentID Subgrapy deployment updated
     */
    function _updateRewards(bytes32 _subgraphDeploymentID) internal returns (uint256) {
        IRewardsManager rewardsManager = rewardsManager();
        if (address(rewardsManager) != address(0)) {
            return rewardsManager.onSubgraphSignalUpdate(_subgraphDeploymentID);
        }
        return 0;
    }

    /**
     * @dev Exter
     */
    function getTotalTokens() external override view returns (uint256) {
        return totalTokens;
    }
}
