// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.6;

// solhint-disable use-natspec

import { Managed } from "../governance/Managed.sol";
import { GraphUpgradeable } from "../upgrades/GraphUpgradeable.sol";

contract ManagedMock is Managed, GraphUpgradeable {
    function initialize(address _controller) external onlyImpl {
        Managed._initialize(_controller);
    }

    function checkNotPartialPaused() external view notPartialPaused {}

    function checkNotPaused() external view notPaused {}

    function checkOnlyGovernor() external view onlyGovernor {}

    /// curation, epochManager, rewardsManager, staking, graphToken, graphTokenGateway, gns — in that order
    function resolveAll() external view returns (address[7] memory) {
        return
            [
                address(curation()),
                address(epochManager()),
                address(rewardsManager()),
                address(staking()),
                address(graphToken()),
                address(graphTokenGateway()),
                address(gns())
            ];
    }
}
