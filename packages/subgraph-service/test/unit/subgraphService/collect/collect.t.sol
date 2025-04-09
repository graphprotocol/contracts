// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";

import { ISubgraphService } from "../../../../contracts/interfaces/ISubgraphService.sol";
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
