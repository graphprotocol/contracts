// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";
import { RecurringCollector } from "../../../contracts/payments/collectors/RecurringCollector.sol";
import { AuthorizableHelper } from "../../utilities/Authorizable.t.sol";
import { Bounder } from "../../utils/Bounder.t.sol";

contract RecurringCollectorHelper is AuthorizableHelper, Bounder {
    RecurringCollector public collector;

    constructor(
        RecurringCollector collector_
    ) AuthorizableHelper(collector_, collector_.REVOKE_AUTHORIZATION_THAWING_PERIOD()) {
        collector = collector_;
    }

    function generateSignedRCA(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 signerPrivateKey
    ) public view returns (IRecurringCollector.SignedRCA memory) {
        bytes32 messageHash = collector.encodeRCA(rca);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IRecurringCollector.SignedRCA memory signedRCA = IRecurringCollector.SignedRCA({
            rca: rca,
            signature: signature
        });

        return signedRCA;
    }

    function generateSignedRCAU(
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau,
        uint256 signerPrivateKey
    ) public view returns (IRecurringCollector.SignedRCAU memory) {
        bytes32 messageHash = collector.encodeRCAU(rcau);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: signature
        });

        return signedRCAU;
    }

    function withElapsedAcceptDeadline(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) public view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        require(block.timestamp > 0, "block.timestamp can't be zero");
        rca.deadline = bound(rca.deadline, 0, block.timestamp - 1);
        return rca;
    }

    function withOKAcceptDeadline(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) public view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        rca.deadline = boundTimestampMin(rca.deadline, block.timestamp);
        return rca;
    }
}
