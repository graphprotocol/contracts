// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IHorizonStaking } from "@graphprotocol/contracts/contracts/staking/IHorizonStaking.sol";

library ProvisionGetter {
    using ProvisionGetter for IHorizonStaking.Provision;

    error ProvisionNotFound(address serviceProvider, address service);

    function get(
        IHorizonStaking graphStaking,
        address serviceProvider
    ) internal view returns (IHorizonStaking.Provision memory) {
        IHorizonStaking.Provision memory provision = graphStaking.getProvision(serviceProvider, address(this));
        if (provision.createdAt == 0) {
            revert ProvisionNotFound(serviceProvider, address(this));
        }
        return provision;
    }
}
