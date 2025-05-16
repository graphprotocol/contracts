// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.27;

import { IGraphToken } from "@graphprotocol/contracts/contracts/token/IGraphToken.sol";
import { IHorizonStaking } from "../../../contracts/interfaces/IHorizonStaking.sol";
import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsEscrow } from "../../../contracts/interfaces/IPaymentsEscrow.sol";

import { IController } from "@graphprotocol/contracts/contracts/governance/IController.sol";
import { IEpochManager } from "@graphprotocol/contracts/contracts/epochs/IEpochManager.sol";
import { IRewardsManager } from "@graphprotocol/contracts/contracts/rewards/IRewardsManager.sol";
import { ITokenGateway } from "@graphprotocol/contracts/contracts/arbitrum/ITokenGateway.sol";
import { IGraphProxyAdmin } from "../../../contracts/interfaces/IGraphProxyAdmin.sol";
import { ICuration } from "@graphprotocol/contracts/contracts/curation/ICuration.sol";

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
