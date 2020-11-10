// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.3;

import "./IManaged.sol";
import "./IController.sol";
import "../curation/ICuration.sol";
import "../epochs/IEpochManager.sol";
import "../rewards/IRewardsManager.sol";
import "../staking/IStaking.sol";
import "../token/IGraphToken.sol";

/**
 * @title Graph Managed contract
 * @dev The Managed contract provides an interface for contracts to interact with the Controller
 * Inspired by Livepeer:
 * https://github.com/livepeer/protocol/blob/streamflow/contracts/Controller.sol
 */
contract Managed {
    // Controller that contract is registered with
    IController public controller;

    event ParameterUpdated(string param);
    event SetController(address controller);

    function _notPartialPaused() internal view {
        require(!controller.paused(), "Paused");
        require(!controller.partialPaused(), "Partial-paused");
    }

    function _notPaused() internal view {
        require(!controller.paused(), "Paused");
    }

    function _onlyGovernor() internal view {
        require(msg.sender == controller.getGovernor(), "Caller must be Controller governor");
    }

    modifier notPartialPaused {
        _notPartialPaused();
        _;
    }

    modifier notPaused {
        _notPaused();
        _;
    }

    // Check if sender is controller
    modifier onlyController() {
        require(msg.sender == address(controller), "Caller must be Controller");
        _;
    }

    modifier onlyGovernor() {
        _onlyGovernor();
        _;
    }

    modifier onlyStaking() {
        require(msg.sender == address(staking()), "Caller must be the staking contract");
        _;
    }

    modifier onlyCuration() {
        require(msg.sender == address(curation()), "Caller must be the curation contract");
        _;
    }

    /**
     * @dev Initialize the controller
     */
    function _initialize(address _controller) internal {
        controller = IController(_controller);
    }

    /**
     * @notice Set Controller. Only callable by current controller
     * @param _controller Controller contract address
     */
    function setController(address _controller) external onlyController {
        controller = IController(_controller);
        emit SetController(_controller);
    }

    /**
     * @dev Return Curation interface
     * @return Curation contract registered with Controller
     */
    function curation() internal view returns (ICuration) {
        return ICuration(controller.getContractProxy(keccak256("Curation")));
    }

    /**
     * @dev Return EpochManager interface
     * @return Epoch manager contract registered with Controller
     */
    function epochManager() internal view returns (IEpochManager) {
        return IEpochManager(controller.getContractProxy(keccak256("EpochManager")));
    }

    /**
     * @dev Return RewardsManager interface
     * @return Rewards manager contract registered with Controller
     */
    function rewardsManager() internal view returns (IRewardsManager) {
        return IRewardsManager(controller.getContractProxy(keccak256("RewardsManager")));
    }

    /**
     * @dev Return Staking interface
     * @return Staking contract registered with Controller
     */
    function staking() internal view returns (IStaking) {
        return IStaking(controller.getContractProxy(keccak256("Staking")));
    }

    /**
     * @dev Return GraphToken interface
     * @return Graph token contract registered with Controller
     */
    function graphToken() internal view returns (IGraphToken) {
        return IGraphToken(controller.getContractProxy(keccak256("GraphToken")));
    }
}
