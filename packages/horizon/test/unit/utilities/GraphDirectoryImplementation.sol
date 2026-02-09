// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IGraphToken } from "@graphprotocol/interfaces/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStaking } from "@graphprotocol/interfaces/contracts/horizon/IHorizonStaking.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IPaymentsEscrow } from "@graphprotocol/interfaces/contracts/horizon/IPaymentsEscrow.sol";

import { IController } from "@graphprotocol/interfaces/contracts/contracts/governance/IController.sol";
import { IEpochManager } from "@graphprotocol/interfaces/contracts/contracts/epochs/IEpochManager.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { ITokenGateway } from "@graphprotocol/interfaces/contracts/contracts/arbitrum/ITokenGateway.sol";
import { IGraphProxyAdmin } from "@graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxyAdmin.sol";
import { ICuration } from "@graphprotocol/interfaces/contracts/contracts/curation/ICuration.sol";

import { GraphDirectory } from "./../../../contracts/utilities/GraphDirectory.sol";

contract GraphDirectoryImplementation is GraphDirectory {
    constructor(address controller) GraphDirectory(controller) {}

    function getContractFromController(bytes memory contractName) external view returns (address) {
        return _graphController().getContractProxy(keccak256(contractName));
    }

    function graphToken() external view returns (IGraphToken) {
        return _graphToken();
    }

    function graphStaking() external view returns (IHorizonStaking) {
        return _graphStaking();
    }

    function graphPayments() external view returns (IGraphPayments) {
        return _graphPayments();
    }

    function graphPaymentsEscrow() external view returns (IPaymentsEscrow) {
        return _graphPaymentsEscrow();
    }

    function graphController() external view returns (IController) {
        return _graphController();
    }

    function graphEpochManager() external view returns (IEpochManager) {
        return _graphEpochManager();
    }

    function graphRewardsManager() external view returns (IRewardsManager) {
        return _graphRewardsManager();
    }

    function graphTokenGateway() external view returns (ITokenGateway) {
        return _graphTokenGateway();
    }

    function graphProxyAdmin() external view returns (IGraphProxyAdmin) {
        return _graphProxyAdmin();
    }

    function graphCuration() external view returns (ICuration) {
        return _graphCuration();
    }
}
