// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IController } from "@graphprotocol/contracts/contracts/governance/IController.sol";
import { IGraphToken } from "../interfaces/IGraphToken.sol";
import { IHorizonStaking } from "../interfaces/IHorizonStaking.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";
import { IGraphEscrow } from "../interfaces/IGraphEscrow.sol";
import { IEpochManager } from "@graphprotocol/contracts/contracts/epochs/IEpochManager.sol";
import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";
import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";
import { ITokenGateway } from "@graphprotocol/contracts/contracts/arbitrum/ITokenGateway.sol";

/**
 * @title GraphDirectory contract
 * @notice This contract is meant to be inherited by other contracts that
 * need to keep track of the addresses of the core Graph Horizon contracts.
 * It fetches the addresses from the Controller supplied during construction,
 * and uses immutable variables to minimize gas costs.
 */
abstract contract GraphDirectory {
    IController private immutable GRAPH_CONTROLLER;

    // Graph Horizon contracts
    IGraphToken private immutable GRAPH_TOKEN;
    IHorizonStaking private immutable GRAPH_STAKING;
    IGraphPayments private immutable GRAPH_PAYMENTS;
    IGraphEscrow private immutable GRAPH_ESCROW;

    // Legacy Graph contracts
    // Required for StakingBackwardCompatibility
    // TODO: remove these once StakingBackwardCompatibility is removed
    IEpochManager private immutable GRAPH_EPOCH_MANAGER;
    IRewardsManager private immutable GRAPH_REWARDS_MANAGER;
    ICuration private immutable GRAPH_CURATION;
    ITokenGateway private immutable GRAPH_TOKEN_GATEWAY;

    event GraphDirectoryInitialized(
        IController graphController,
        IGraphToken graphToken,
        IHorizonStaking graphStaking,
        IGraphPayments graphPayments,
        IGraphEscrow graphEscrow,
        IEpochManager graphEpochManager,
        IRewardsManager graphRewardsManager,
        ICuration graphCuration,
        ITokenGateway graphTokenGateway
    );

    error GraphDirectoryInvalidZeroAddress();

    constructor(address controller) {
        if (controller == address(0)) {
            revert GraphDirectoryInvalidZeroAddress();
        }
        GRAPH_CONTROLLER = IController(controller);

        GRAPH_TOKEN = IGraphToken(_getContractFromController("GraphToken"));
        GRAPH_STAKING = IHorizonStaking(_getContractFromController("Staking"));
        GRAPH_PAYMENTS = IGraphPayments(_getContractFromController("GraphPayments"));
        GRAPH_ESCROW = IGraphEscrow(_getContractFromController("GraphEscrow"));
        GRAPH_EPOCH_MANAGER = IEpochManager(_getContractFromController("EpochManager"));
        GRAPH_REWARDS_MANAGER = IRewardsManager(_getContractFromController("RewardsManager"));
        GRAPH_CURATION = ICuration(_getContractFromController("Curation"));
        GRAPH_TOKEN_GATEWAY = ITokenGateway(_getContractFromController("GraphTokenGateway"));

        emit GraphDirectoryInitialized(
            GRAPH_CONTROLLER,
            GRAPH_TOKEN,
            GRAPH_STAKING,
            GRAPH_PAYMENTS,
            GRAPH_ESCROW,
            GRAPH_EPOCH_MANAGER,
            GRAPH_REWARDS_MANAGER,
            GRAPH_CURATION,
            GRAPH_TOKEN_GATEWAY
        );
    }

    function _graphController() internal view returns (IController) {
        return GRAPH_CONTROLLER;
    }

    function _graphToken() internal view returns (IGraphToken) {
        return GRAPH_TOKEN;
    }

    function _graphStaking() internal view returns (IHorizonStaking) {
        return GRAPH_STAKING;
    }

    function _graphPayments() internal view returns (IGraphPayments) {
        return GRAPH_PAYMENTS;
    }

    function _graphEscrow() internal view returns (IGraphEscrow) {
        return GRAPH_ESCROW;
    }

    function _graphEpochManager() internal view returns (IEpochManager) {
        return GRAPH_EPOCH_MANAGER;
    }

    function _graphRewardsManager() internal view returns (IRewardsManager) {
        return GRAPH_REWARDS_MANAGER;
    }

    function _graphCuration() internal view returns (ICuration) {
        return GRAPH_CURATION;
    }

    function _graphTokenGateway() internal view returns (ITokenGateway) {
        return GRAPH_TOKEN_GATEWAY;
    }

    function _getContractFromController(bytes memory __contractName) private view returns (address) {
        address contractAddress = GRAPH_CONTROLLER.getContractProxy(keccak256(contractName));
        if (contractAddress == address(0)) {
            revert GraphDirectoryInvalidZeroAddress();
        }
        return contractAddress;
    }
}
