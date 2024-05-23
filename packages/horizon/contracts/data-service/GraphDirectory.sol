// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import { IGraphToken } from "../interfaces/IGraphToken.sol";
import { IHorizonStaking } from "../interfaces/IHorizonStaking.sol";
import { IGraphPayments } from "../interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../interfaces/IPaymentsEscrow.sol";

import { IController } from "@graphprotocol/contracts/contracts/governance/IController.sol";
import { IEpochManager } from "@graphprotocol/contracts/contracts/epochs/IEpochManager.sol";
import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";
import { ITokenGateway } from "@graphprotocol/contracts/contracts/arbitrum/ITokenGateway.sol";
import { IBridgeEscrow } from "@graphprotocol/contracts/contracts/gateway/IBridgeEscrow.sol";
import { IGraphProxyAdmin } from "@graphprotocol/contracts/contracts/upgrades/IGraphProxyAdmin.sol";

import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";

/**
 * @title GraphDirectory contract
 * @notice This contract is meant to be inherited by other contracts that
 * need to keep track of the addresses in Graph Horizon contracts.
 * It fetches the addresses from the Controller supplied during construction,
 * and uses immutable variables to minimize gas costs.
 */
abstract contract GraphDirectory {
    // Graph Horizon contracts
    IGraphToken private immutable GRAPH_TOKEN;
    IHorizonStaking private immutable GRAPH_STAKING;
    IGraphPayments private immutable GRAPH_PAYMENTS;
    IPaymentsEscrow private immutable GRAPH_PAYMENTS_ESCROW;

    // Graph periphery contracts
    IController private immutable GRAPH_CONTROLLER;
    IEpochManager private immutable GRAPH_EPOCH_MANAGER;
    IRewardsManager private immutable GRAPH_REWARDS_MANAGER;
    ITokenGateway private immutable GRAPH_TOKEN_GATEWAY;
    IBridgeEscrow private immutable GRAPH_BRIDGE_ESCROW;
    IGraphProxyAdmin private immutable GRAPH_PROXY_ADMIN;

    // Legacy Graph contracts - required for StakingBackwardCompatibility
    // TODO: remove these once StakingBackwardCompatibility is removed
    ICuration private immutable GRAPH_CURATION;

    event GraphDirectoryInitialized(
        IGraphToken graphToken,
        IHorizonStaking graphStaking,
        IGraphPayments graphPayments,
        IPaymentsEscrow graphEscrow,
        IController graphController,
        IEpochManager graphEpochManager,
        IRewardsManager graphRewardsManager,
        ITokenGateway graphTokenGateway,
        IBridgeEscrow graphBridgeEscrow,
        IGraphProxyAdmin graphProxyAdmin,
        ICuration graphCuration
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
        GRAPH_PAYMENTS_ESCROW = IPaymentsEscrow(_getContractFromController("PaymentsEscrow"));
        GRAPH_EPOCH_MANAGER = IEpochManager(_getContractFromController("EpochManager"));
        GRAPH_REWARDS_MANAGER = IRewardsManager(_getContractFromController("RewardsManager"));
        GRAPH_TOKEN_GATEWAY = ITokenGateway(_getContractFromController("GraphTokenGateway"));
        GRAPH_BRIDGE_ESCROW = IBridgeEscrow(_getContractFromController("BridgeEscrow"));
        GRAPH_PROXY_ADMIN = IGraphProxyAdmin(_getContractFromController("GraphProxyAdmin"));
        GRAPH_CURATION = ICuration(_getContractFromController("Curation"));

        emit GraphDirectoryInitialized(
            GRAPH_TOKEN,
            GRAPH_STAKING,
            GRAPH_PAYMENTS,
            GRAPH_PAYMENTS_ESCROW,
            GRAPH_CONTROLLER,
            GRAPH_EPOCH_MANAGER,
            GRAPH_REWARDS_MANAGER,
            GRAPH_TOKEN_GATEWAY,
            GRAPH_BRIDGE_ESCROW,
            GRAPH_PROXY_ADMIN,
            GRAPH_CURATION
        );
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

    function _graphPaymentsEscrow() internal view returns (IPaymentsEscrow) {
        return GRAPH_PAYMENTS_ESCROW;
    }

    function _graphController() internal view returns (IController) {
        return GRAPH_CONTROLLER;
    }

    function _graphEpochManager() internal view returns (IEpochManager) {
        return GRAPH_EPOCH_MANAGER;
    }

    function _graphRewardsManager() internal view returns (IRewardsManager) {
        return GRAPH_REWARDS_MANAGER;
    }

    function _graphTokenGateway() internal view returns (ITokenGateway) {
        return GRAPH_TOKEN_GATEWAY;
    }

    function _graphBridgeEscrow() internal view returns (IBridgeEscrow) {
        return GRAPH_BRIDGE_ESCROW;
    }

    function _graphProxyAdmin() internal view returns (IGraphProxyAdmin) {
        return GRAPH_PROXY_ADMIN;
    }

    function _graphCuration() internal view returns (ICuration) {
        return GRAPH_CURATION;
    }

    function _getContractFromController(bytes memory _contractName) private view returns (address) {
        address contractAddress = GRAPH_CONTROLLER.getContractProxy(keccak256(_contractName));
        if (contractAddress == address(0)) {
            revert GraphDirectoryInvalidZeroAddress();
        }
        return contractAddress;
    }
}
