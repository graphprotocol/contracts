// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IHorizonStaking } from "../../interfaces/IHorizonStaking.sol";

library ProvisionGetter {
    using ProvisionGetter for IHorizonStaking.Provision;

    error ProvisionGetterProvisionNotFound(address serviceProvider, address service);

    function get(
        IHorizonStaking graphStaking,
        address serviceProvider
    ) internal view returns (IHorizonStaking.Provision memory) {
        IHorizonStaking.Provision memory provision = graphStaking.getProvision(serviceProvider, address(this));
        if (provision.createdAt == 0) {
            revert ProvisionGetterProvisionNotFound(serviceProvider, address(this));
        }
        return provision;
    }
}
