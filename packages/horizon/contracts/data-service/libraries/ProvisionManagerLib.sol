// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IHorizonStaking } from "../../interfaces/IHorizonStaking.sol";
import { ProvisionManager } from "../utilities/ProvisionManager.sol";

library ProvisionManagerLib {
    function requireAuthorizedForProvision(
        IHorizonStaking graphStaking,
        address serviceProvider,
        address dataService,
        address operator
    ) external view {
        require(
            graphStaking.isAuthorized(serviceProvider, dataService, operator),
            ProvisionManager.ProvisionManagerNotAuthorized(serviceProvider, operator)
        );
    }
}
