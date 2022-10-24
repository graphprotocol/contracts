// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

import "./IController.sol";

import "../curation/ICuration.sol";
import "../epochs/IEpochManager.sol";
import "../rewards/IRewardsManager.sol";
import "../staking/IStaking.sol";
import "../token/IGraphToken.sol";
import "../arbitrum/ITokenGateway.sol";

/**
 * @title Graph Managed contract
 * @dev The Managed contract provides an interface to interact with the Controller.
 * It also provides local caching for contract addresses. This mechanism relies on calling the
 * public `syncAllContracts()` function whenever a contract changes in the controller.
 *
 * Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
contract Managed {
    // -- State --

    // Controller that contract is registered with
    IController public controller;
    mapping(bytes32 => address) private addressCache;
    uint256[10] private __gap;

    // Immutables
    bytes32 private immutable CURATION = keccak256("Curation");
    bytes32 private immutable EPOCH_MANAGER = keccak256("EpochManager");
    bytes32 private immutable REWARDS_MANAGER = keccak256("RewardsManager");
    bytes32 private immutable STAKING = keccak256("Staking");
    bytes32 private immutable GRAPH_TOKEN = keccak256("GraphToken");
    bytes32 private immutable GRAPH_TOKEN_GATEWAY = keccak256("GraphTokenGateway");

    // -- Events --

    event ParameterUpdated(string param);
    event SetController(address controller);

    /**
     * @dev Emitted when contract with `nameHash` is synced to `contractAddress`.
     */
    event ContractSynced(bytes32 indexed nameHash, address contractAddress);

    // -- Modifiers --

    function _notPartialPaused() internal view {
        require(!controller.paused(), "Paused");
        require(!controller.partialPaused(), "Partial-paused");
    }

    function _notPaused() internal view virtual {
        require(!controller.paused(), "Paused");
    }

    function _onlyGovernor() internal view {
        require(msg.sender == controller.getGovernor(), "Only Controller governor");
    }

    function _onlyController() internal view {
        require(msg.sender == address(controller), "Caller must be Controller");
    }

    modifier notPartialPaused() {
        _notPartialPaused();
        _;
    }

    modifier notPaused() {
        _notPaused();
        _;
    }

    // Check if sender is controller.
    modifier onlyController() {
        _onlyController();
        _;
    }

    // Check if sender is the governor.
    modifier onlyGovernor() {
        _onlyGovernor();
        _;
    }

    // -- Functions --

    /**
     * @dev Initialize the controller.
     */
    function _initialize(address _controller) internal {
        _setController(_controller);
    }

    /**
     * @notice Set Controller. Only callable by current controller.
     * @param _controller Controller contract address
     */
    function setController(address _controller) external onlyController {
        _setController(_controller);
    }

    /**
     * @dev Set controller.
     * @param _controller Controller contract address
     */
    function _setController(address _controller) internal {
        require(_controller != address(0), "Controller must be set");
        controller = IController(_controller);
        emit SetController(_controller);
    }

    /**
     * @dev Return Curation interface.
     * @return Curation contract registered with Controller
     */
    function curation() internal view returns (ICuration) {
        return ICuration(_resolveContract(CURATION));
    }

    /**
     * @dev Return EpochManager interface.
     * @return Epoch manager contract registered with Controller
     */
    function epochManager() internal view returns (IEpochManager) {
        return IEpochManager(_resolveContract(EPOCH_MANAGER));
    }

    /**
     * @dev Return RewardsManager interface.
     * @return Rewards manager contract registered with Controller
     */
    function rewardsManager() internal view returns (IRewardsManager) {
        return IRewardsManager(_resolveContract(REWARDS_MANAGER));
    }

    /**
     * @dev Return Staking interface.
     * @return Staking contract registered with Controller
     */
    function staking() internal view returns (IStaking) {
        return IStaking(_resolveContract(STAKING));
    }

    /**
     * @dev Return GraphToken interface.
     * @return Graph token contract registered with Controller
     */
    function graphToken() internal view returns (IGraphToken) {
        return IGraphToken(_resolveContract(GRAPH_TOKEN));
    }

    /**
     * @dev Return GraphTokenGateway (L1 or L2) interface.
     * @return Graph token gateway contract registered with Controller
     */
    function graphTokenGateway() internal view returns (ITokenGateway) {
        return ITokenGateway(_resolveContract(GRAPH_TOKEN_GATEWAY));
    }

    /**
     * @dev Resolve a contract address from the cache or the Controller if not found.
     * @return Address of the contract
     */
    function _resolveContract(bytes32 _nameHash) internal view returns (address) {
        address contractAddress = addressCache[_nameHash];
        if (contractAddress == address(0)) {
            contractAddress = controller.getContractProxy(_nameHash);
        }
        return contractAddress;
    }

    /**
     * @dev Cache a contract address from the Controller registry.
     * @param _name Name of the contract to sync into the cache
     */
    function _syncContract(string memory _name) internal {
        bytes32 nameHash = keccak256(abi.encodePacked(_name));
        address contractAddress = controller.getContractProxy(nameHash);
        if (addressCache[nameHash] != contractAddress) {
            addressCache[nameHash] = contractAddress;
            emit ContractSynced(nameHash, contractAddress);
        }
    }

    /**
     * @dev Sync protocol contract addresses from the Controller registry.
     * This function will cache all the contracts using the latest addresses
     * Anyone can call the function whenever a Proxy contract change in the
     * controller to ensure the protocol is using the latest version
     */
    function syncAllContracts() external {
        _syncContract("Curation");
        _syncContract("EpochManager");
        _syncContract("RewardsManager");
        _syncContract("Staking");
        _syncContract("GraphToken");
        _syncContract("GraphTokenGateway");
    }
}
