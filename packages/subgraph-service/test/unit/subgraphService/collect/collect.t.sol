// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";

import { ISubgraphService } from "@graphprotocol/interfaces/contracts/subgraph-service/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceCollectTest is SubgraphServiceTest {
    /*
     * TESTS
     */

    function test_SubgraphService_Collect_RevertWhen_InvalidPayment(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes invalidPaymentType = IGraphPayments.PaymentTypes.IndexingFee;
        vm.expectRevert(
            abi.encodeWithSelector(ISubgraphService.SubgraphServiceInvalidPaymentType.selector, invalidPaymentType)
        );
        subgraphService.collect(users.indexer, invalidPaymentType, "");
    }
}
