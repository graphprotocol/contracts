// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceRegisterTest is SubgraphServiceTest {

    /*
     * TESTS
     */

    function testCollect_Tokens(uint256 tokens) public useIndexer useAllocation(tokens) {
        
    }

    function testCollect_RevertWhen_InvalidPayment(
        uint256 tokens
    ) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes invalidPaymentType = IGraphPayments.PaymentTypes.IndexingFee;
        vm.expectRevert(abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceInvalidPaymentType.selector,
            invalidPaymentType
        ));
        subgraphService.collect(users.indexer, invalidPaymentType, "");
    }
}
