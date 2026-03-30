// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IRecurringCollector } from "@graphprotocol/interfaces/contracts/horizon/IRecurringCollector.sol";
import { IProviderEligibility } from "@graphprotocol/interfaces/contracts/issuance/eligibility/IProviderEligibility.sol";
import { RecurringCollector } from "../../../../contracts/payments/collectors/RecurringCollector.sol";
import { Bounder } from "../../../unit/utils/Bounder.t.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract RecurringCollectorHelper is Bounder {
    RecurringCollector public collector;
    address public proxyAdmin;

    constructor(RecurringCollector collector_, address proxyAdmin_) {
        collector = collector_;
        proxyAdmin = proxyAdmin_;
    }

    function withElapsedAcceptDeadline(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) public view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        require(block.timestamp > 0, "block.timestamp can't be zero");
        require(block.timestamp <= type(uint64).max, "block.timestamp can't be huge");
        rca.deadline = uint64(bound(rca.deadline, 0, block.timestamp - 1));
        return rca;
    }

    function withOKAcceptDeadline(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) public view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        require(block.timestamp <= type(uint64).max, "block.timestamp can't be huge");
        rca.deadline = uint64(boundTimestampMin(rca.deadline, block.timestamp));
        return rca;
    }

    function sensibleRCA(
        IRecurringCollector.RecurringCollectionAgreement memory rca
    ) public view returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        vm.assume(uint160(rca.dataService) > 0xFF);
        vm.assume(uint160(rca.payer) > 0xFF);
        vm.assume(uint160(rca.serviceProvider) > 0xFF);
        // Exclude ProxyAdmin address — TransparentProxy routes admin calls to ProxyAdmin, not implementation
        vm.assume(rca.dataService != proxyAdmin);
        vm.assume(rca.payer != proxyAdmin);
        vm.assume(rca.serviceProvider != proxyAdmin);
        // Prevent role collisions — cancel() resolves role by address priority
        vm.assume(rca.payer != rca.serviceProvider);
        vm.assume(rca.payer != rca.dataService);
        vm.assume(rca.serviceProvider != rca.dataService);

        // Ensure we have a nonce if it's zero
        if (rca.nonce == 0) {
            rca.nonce = 1;
        }

        rca.minSecondsPerCollection = _sensibleMinSecondsPerCollection(rca.minSecondsPerCollection);
        rca.maxSecondsPerCollection = _sensibleMaxSecondsPerCollection(
            rca.maxSecondsPerCollection,
            rca.minSecondsPerCollection
        );

        rca.deadline = _sensibleDeadline(rca.deadline);
        rca.endsAt = _sensibleEndsAt(rca.endsAt, rca.maxSecondsPerCollection);

        rca.maxInitialTokens = _sensibleMaxInitialTokens(rca.maxInitialTokens);
        rca.maxOngoingTokensPerSecond = _sensibleMaxOngoingTokensPerSecond(rca.maxOngoingTokensPerSecond);

        // CONDITION_ELIGIBILITY_CHECK requires payer to support IProviderEligibility via ERC-165.
        // Mask it out in fuzz-generated offers when the payer can't satisfy the check.
        if (!ERC165Checker.supportsInterface(rca.payer, type(IProviderEligibility).interfaceId)) {
            rca.conditions = rca.conditions & ~uint16(collector.CONDITION_ELIGIBILITY_CHECK());
        }

        return rca;
    }

    function sensibleRCAU(
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau
    ) public view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        return sensibleRCAU(rcau, address(0));
    }

    function sensibleRCAU(
        IRecurringCollector.RecurringCollectionAgreementUpdate memory rcau,
        address payer
    ) public view returns (IRecurringCollector.RecurringCollectionAgreementUpdate memory) {
        rcau.minSecondsPerCollection = _sensibleMinSecondsPerCollection(rcau.minSecondsPerCollection);
        rcau.maxSecondsPerCollection = _sensibleMaxSecondsPerCollection(
            rcau.maxSecondsPerCollection,
            rcau.minSecondsPerCollection
        );

        rcau.deadline = _sensibleDeadline(rcau.deadline);
        rcau.endsAt = _sensibleEndsAt(rcau.endsAt, rcau.maxSecondsPerCollection);
        rcau.maxInitialTokens = _sensibleMaxInitialTokens(rcau.maxInitialTokens);
        rcau.maxOngoingTokensPerSecond = _sensibleMaxOngoingTokensPerSecond(rcau.maxOngoingTokensPerSecond);

        // CONDITION_ELIGIBILITY_CHECK requires payer to support IProviderEligibility via ERC-165.
        // Mask it out in fuzz-generated updates when the payer can't satisfy the check.
        if (payer != address(0) && !ERC165Checker.supportsInterface(payer, type(IProviderEligibility).interfaceId)) {
            rcau.conditions = rcau.conditions & ~uint16(collector.CONDITION_ELIGIBILITY_CHECK());
        }

        return rcau;
    }

    function _sensibleDeadline(uint256 _seed) internal view returns (uint64) {
        return
            uint64(
                bound(_seed, block.timestamp + 1, block.timestamp + uint256(collector.MIN_SECONDS_COLLECTION_WINDOW()))
            ); // between now and +MIN_SECONDS_COLLECTION_WINDOW
    }

    function _sensibleEndsAt(uint256 _seed, uint32 _maxSecondsPerCollection) internal view returns (uint64) {
        return
            uint64(
                bound(
                    _seed,
                    block.timestamp + (10 * uint256(_maxSecondsPerCollection)),
                    block.timestamp + (1_000_000 * uint256(_maxSecondsPerCollection))
                )
            ); // between 10 and 1M max collections
    }

    function _sensibleMaxSecondsPerCollection(
        uint32 _seed,
        uint32 _minSecondsPerCollection
    ) internal view returns (uint32) {
        return
            uint32(
                bound(
                    _seed,
                    _minSecondsPerCollection + uint256(collector.MIN_SECONDS_COLLECTION_WINDOW()),
                    60 * 60 * 24 * 30
                ) // between minSecondsPerCollection + 2h and 30 days
            );
    }

    function _sensibleMaxInitialTokens(uint256 _seed) internal pure returns (uint256) {
        return bound(_seed, 0, 1e18 * 100_000_000); // between 0 and 100M tokens
    }

    function _sensibleMaxOngoingTokensPerSecond(uint256 _seed) internal pure returns (uint256) {
        return bound(_seed, 1, 1e18); // between 1 and 1e18 tokens per second
    }

    function _sensibleMinSecondsPerCollection(uint32 _seed) internal pure returns (uint32) {
        return uint32(bound(_seed, 10 * 60, 24 * 60 * 60)); // between 10 min and 24h
    }
}
