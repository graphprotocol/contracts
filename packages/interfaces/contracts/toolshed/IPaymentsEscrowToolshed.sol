// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

// solhint-disable use-natspec

import { IPaymentsEscrow } from "../horizon/IPaymentsEscrow.sol";

interface IPaymentsEscrowToolshed is IPaymentsEscrow {
    function escrowAccounts(
        address payer,
        address collector,
        address receiver
    ) external view returns (EscrowAccount memory);
}
