// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { IndexingAgreementDecoder } from "../../../../contracts/libraries/IndexingAgreementDecoder.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceCollectTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Collect_RevertWhen_InvalidPayment(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes.IndexingFee;
        vm.expectRevert(
            abi.encodeWithSelector(
                IndexingAgreementDecoder.IndexingAgreementDecoderInvalidData.selector,
                "decodeCollectData",
                ""
            )
        );
        subgraphService.collect(users.indexer, paymentType, "");
    }
}
