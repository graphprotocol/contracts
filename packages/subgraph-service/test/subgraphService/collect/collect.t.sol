// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IDataService } from "@graphprotocol/horizon/contracts/data-service/interfaces/IDataService.sol";
import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { ITAPCollector } from "@graphprotocol/horizon/contracts/interfaces/ITAPCollector.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceRegisterTest is SubgraphServiceTest {

    address signer;
    uint256 signerPrivateKey;

    /*
     * HELPERS
     */

    function _getRAV() private view returns (ITAPCollector.ReceiptAggregateVoucher memory rav) {
        return ITAPCollector.ReceiptAggregateVoucher({
            dataService: address(subgraphService),
            serviceProvider: users.indexer,
            timestampNs: 0,
            valueAggregate: 0,
            metadata: abi.encode(allocationID)
        });
    }

    /*
     * SET UP
     */

    function setUp() public virtual override {
        super.setUp();
        (signer, signerPrivateKey) = makeAddrAndKey("signer");
    }

    /*
     * TESTS
     */

    function testCollect_QueryFees(uint256 tokens) public useIndexer useAllocation(tokens) {
        IGraphPayments.PaymentTypes invalidPaymentType = IGraphPayments.PaymentTypes.QueryFee;
        ITAPCollector.ReceiptAggregateVoucher memory rav = _getRAV();
        bytes32 messageHash = tapCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory data = abi.encode(rav, r, s, v);
        subgraphService.collect(users.indexer, invalidPaymentType, data);
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
