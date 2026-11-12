// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IManaged } from "@graphprotocol/interfaces/contracts/contracts/governance/IManaged.sol";
import { IRewardsManager } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManager.sol";
import { IRewardsManagerDeprecated } from "@graphprotocol/interfaces/contracts/contracts/rewards/IRewardsManagerDeprecated.sol";
import { IIssuanceTarget } from "@graphprotocol/interfaces/contracts/issuance/allocate/IIssuanceTarget.sol";
import { IProviderEligibilityManagement } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibilityManagement.sol";

/// Every interface RewardsManager implements, plus the initializer, storage getters and events they omit.
interface IRewardsManagerLike is
    IRewardsManager,
    IRewardsManagerDeprecated,
    IManaged,
    IIssuanceTarget,
    IProviderEligibilityManagement,
    IERC165
{
    event ParameterUpdated(string param);

    function initialize(address controller) external;

    function accRewardsPerSignal() external view returns (uint256);

    function accRewardsPerSignalLastBlockUpdated() external view returns (uint256);

    function subgraphAvailabilityOracle() external view returns (address);

    function subgraphs(
        bytes32 subgraphDeploymentId
    )
        external
        view
        returns (
            uint256 accRewardsForSubgraph,
            uint256 accRewardsForSubgraphSnapshot,
            uint256 accRewardsPerSignalSnapshot,
            uint256 accRewardsPerAllocatedToken
        );

    function denylist(bytes32 subgraphDeploymentId) external view returns (uint256);

    function minimumSubgraphSignal() external view returns (uint256);
}
