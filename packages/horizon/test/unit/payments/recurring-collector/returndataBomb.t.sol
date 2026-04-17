// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IGraphPayments } from "@graphprotocol/interfaces/contracts/horizon/IGraphPayments.sol";
import { IAgreementOwner } from "@graphprotocol/interfaces/contracts/horizon/IAgreementOwner.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { OFFER_TYPE_NEW } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

/// @notice Payer that returns a configurable-size buffer from every callback.
/// Used to verify the collector caps returndata copy into its outer frame.
contract HugeReturnPayer is IAgreementOwner, IERC165 {
    uint256 public returnBytes = 500_000;

    function setReturnBytes(uint256 size) external {
        returnBytes = size;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IProviderEligibility).interfaceId;
    }

    function beforeCollection(bytes16, uint256) external {
        uint256 size = returnBytes;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            return(0, size)
        }
    }

    function afterCollection(bytes16, uint256) external {
        uint256 size = returnBytes;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            return(0, size)
        }
    }

    /// @notice isEligible — first 32 bytes = 1 (eligible), remainder is memory-expansion padding.
    fallback() external {
        uint256 size = returnBytes;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0, 1)
            return(0, size)
        }
    }
}

contract RecurringCollectorReturndataBombTest is RecurringCollectorSharedTest {
    /* solhint-disable graph/func-name-mixedcase */

    /// @notice All three payer callbacks return 500KB. With bounded retSize at each call site
    /// the outer frame does not copy the returndata, so gas usage stays proportional to the
    /// callbacks' own internal work. Without the bound, the outer frame incurs memory expansion
    /// + RETURNDATACOPY for each 500KB payload, roughly doubling gas consumption.
    function test_Collect_BoundsReturndataCopy_WhenPayerReturnsHuge() public {
        HugeReturnPayer attacker = new HugeReturnPayer();
        attacker.setReturnBytes(500_000);

        IRecurringCollector.RecurringCollectionAgreement memory rca = _recurringCollectorHelper.sensibleRCA(
            IRecurringCollector.RecurringCollectionAgreement({
                deadline: uint64(block.timestamp + 1 hours),
                endsAt: uint64(block.timestamp + 365 days),
                payer: address(attacker),
                dataService: makeAddr("ds"),
                serviceProvider: makeAddr("sp"),
                maxInitialTokens: 100 ether,
                maxOngoingTokensPerSecond: 1 ether,
                minSecondsPerCollection: 600,
                maxSecondsPerCollection: 3600,
                conditions: 0,
                nonce: 1,
                metadata: ""
            })
        );
        rca.conditions = 1; // CONDITION_ELIGIBILITY_CHECK — exercise the eligibility staticcall path

        vm.prank(address(attacker));
        _recurringCollector.offer(OFFER_TYPE_NEW, abi.encode(rca), 0);
        _setupValidProvision(rca.serviceProvider, rca.dataService);

        vm.prank(rca.dataService);
        bytes16 agreementId = _recurringCollector.accept(rca, "");

        skip(rca.minSecondsPerCollection);
        uint256 tokens = 1 ether;
        bytes memory data = _generateCollectData(_generateCollectParams(rca, agreementId, bytes32("col1"), tokens, 0));

        uint256 gasBefore = gasleft();
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(collected, tokens, "collect should succeed despite huge returndata");

        // Bounded frame: base collect (~200k) plus three callbacks' internal 500KB expansion
        // (~520k each) totals roughly 1.8M. Without the bound each callback additionally causes
        // ~520k of outer-frame memory expansion plus the RETURNDATACOPY itself, pushing the
        // total above 3.3M. A 2.5M ceiling cleanly separates the two cases.
        assertLt(gasUsed, 2_500_000, "outer frame consumed unbounded payer returndata");
    }

    /* solhint-enable graph/func-name-mixedcase */
}
