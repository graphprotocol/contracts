// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRecurringAgreementHelper } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementHelper.sol";
import { IRecurringAgreementManagement } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreementManagement.sol";
import { IRecurringAgreements } from "@graphprotocol/interfaces/contracts/issuance/agreement/IRecurringAgreements.sol";
import { IAgreementCollector } from "@graphprotocol/interfaces/contracts/horizon/IAgreementCollector.sol";

/**
 * @title RecurringAgreementHelper
 * @author Edge & Node
 * @notice Stateless, permissionless convenience contract for {RecurringAgreementManager}.
 * Provides batch reconciliation (including cleanup of settled agreements) and
 * read-only audit views. Independently deployable — better versions can be
 * deployed without protocol changes.
 *
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringAgreementHelper is IRecurringAgreementHelper {
    /// @notice The RecurringAgreementManager contract (management interface)
    IRecurringAgreementManagement public immutable MANAGER;

    /// @notice The RecurringAgreementManager contract (read-only interface)
    IRecurringAgreements public immutable AGREEMENTS;

    /// @notice The GRT token contract
    IERC20 public immutable GRAPH_TOKEN;

    /// @notice Thrown when an address parameter is the zero address
    error ZeroAddress();

    /**
     * @notice Constructor for the RecurringAgreementHelper contract
     * @param manager Address of the RecurringAgreementManager contract
     * @param graphToken Address of the GRT token contract
     */
    constructor(address manager, IERC20 graphToken) {
        require(manager != address(0), ZeroAddress());
        require(address(graphToken) != address(0), ZeroAddress());
        MANAGER = IRecurringAgreementManagement(manager);
        AGREEMENTS = IRecurringAgreements(manager);
        GRAPH_TOKEN = graphToken;
    }

    // -- Audit Views --

    /// @inheritdoc IRecurringAgreementHelper
    function auditGlobal() external view returns (GlobalAudit memory audit) {
        audit = GlobalAudit({
            tokenBalance: GRAPH_TOKEN.balanceOf(address(MANAGER)),
            sumMaxNextClaimAll: AGREEMENTS.getSumMaxNextClaimAll(),
            totalEscrowDeficit: AGREEMENTS.getTotalEscrowDeficit(),
            escrowBasis: AGREEMENTS.getEscrowBasis(),
            minOnDemandBasisThreshold: AGREEMENTS.getMinOnDemandBasisThreshold(),
            minFullBasisMargin: AGREEMENTS.getMinFullBasisMargin(),
            collectorCount: AGREEMENTS.getCollectorCount()
        });
    }

    /// @inheritdoc IRecurringAgreementHelper
    function auditPairs(IAgreementCollector collector) external view returns (PairAudit[] memory pairs) {
        return _auditPairs(collector, 0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function auditPairs(
        IAgreementCollector collector,
        uint256 offset,
        uint256 count
    ) external view returns (PairAudit[] memory pairs) {
        return _auditPairs(collector, offset, count);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function auditPair(IAgreementCollector collector, address provider) external view returns (PairAudit memory pair) {
        pair = PairAudit({
            collector: collector,
            provider: provider,
            agreementCount: AGREEMENTS.getPairAgreementCount(collector, provider),
            sumMaxNextClaim: AGREEMENTS.getSumMaxNextClaim(collector, provider),
            escrowSnap: AGREEMENTS.getEscrowSnap(collector, provider),
            escrow: AGREEMENTS.getEscrowAccount(collector, provider)
        });
    }

    // -- Enumeration Views --

    /// @inheritdoc IRecurringAgreementHelper
    function getPairAgreements(
        IAgreementCollector collector,
        address provider
    ) external view returns (bytes16[] memory) {
        return getPairAgreements(collector, provider, 0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getPairAgreements(
        IAgreementCollector collector,
        address provider,
        uint256 offset,
        uint256 count
    ) public view returns (bytes16[] memory result) {
        uint256 total = AGREEMENTS.getPairAgreementCount(collector, provider);
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new bytes16[](0);
        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;
        result = new bytes16[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = AGREEMENTS.getPairAgreementAt(collector, provider, offset + i);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getCollectors() external view returns (address[] memory) {
        return getCollectors(0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getCollectors(uint256 offset, uint256 count) public view returns (address[] memory result) {
        uint256 total = AGREEMENTS.getCollectorCount();
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new address[](0);
        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;
        result = new address[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = address(AGREEMENTS.getCollectorAt(offset + i));
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getProviders(IAgreementCollector collector) external view returns (address[] memory) {
        return getProviders(collector, 0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getProviders(
        IAgreementCollector collector,
        uint256 offset,
        uint256 count
    ) public view returns (address[] memory result) {
        uint256 total = AGREEMENTS.getProviderCount(collector);
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new address[](0);
        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;
        result = new address[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = AGREEMENTS.getProviderAt(collector, offset + i);
    }

    // -- Reconciliation Discovery --

    /// @inheritdoc IRecurringAgreementHelper
    function checkPairStaleness(
        IAgreementCollector collector,
        address provider
    ) external view returns (AgreementStaleness[] memory staleAgreements, bool escrowStale) {
        uint256 count = AGREEMENTS.getPairAgreementCount(collector, provider);
        staleAgreements = new AgreementStaleness[](count);
        for (uint256 i = 0; i < count; ++i) {
            bytes16 id = AGREEMENTS.getPairAgreementAt(collector, provider, i);
            uint256 cached = AGREEMENTS.getAgreementMaxNextClaim(collector, id);
            uint256 live = collector.getMaxNextClaim(id);
            staleAgreements[i] = AgreementStaleness({
                agreementId: id,
                cachedMaxNextClaim: cached,
                liveMaxNextClaim: live,
                stale: cached != live
            });
        }
        escrowStale =
            AGREEMENTS.getEscrowSnap(collector, provider) != AGREEMENTS.getEscrowAccount(collector, provider).balance;
    }

    // -- Reconciliation --

    /// @inheritdoc IRecurringAgreementHelper
    function reconcilePair(
        IAgreementCollector collector,
        address provider
    ) external returns (uint256 removed, bool pairExists) {
        removed = _reconcilePair(collector, provider);
        pairExists = MANAGER.reconcileProvider(collector, provider);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function reconcileCollector(
        IAgreementCollector collector
    ) external returns (uint256 removed, bool collectorExists) {
        // Snapshot providers before iterating (removal modifies the set)
        address[] memory providers = this.getProviders(collector);
        for (uint256 p = 0; p < providers.length; ++p) {
            removed += _reconcilePair(collector, providers[p]);
            MANAGER.reconcileProvider(collector, providers[p]);
        }
        collectorExists = AGREEMENTS.getProviderCount(collector) != 0;
    }

    /// @inheritdoc IRecurringAgreementHelper
    function reconcileAll() external returns (uint256 removed) {
        // Snapshot collectors before iterating
        address[] memory collectors = this.getCollectors();
        for (uint256 c = 0; c < collectors.length; ++c) {
            IAgreementCollector collector = IAgreementCollector(collectors[c]);
            address[] memory providers = this.getProviders(collector);
            for (uint256 p = 0; p < providers.length; ++p) {
                removed += _reconcilePair(collector, providers[p]);
                MANAGER.reconcileProvider(collector, providers[p]);
            }
        }
    }

    // -- Private Helpers --

    function _auditPairs(
        IAgreementCollector collector,
        uint256 offset,
        uint256 count
    ) private view returns (PairAudit[] memory pairs) {
        address[] memory providers = this.getProviders(collector, offset, count);
        pairs = new PairAudit[](providers.length);
        for (uint256 i = 0; i < providers.length; ++i) {
            pairs[i] = PairAudit({
                collector: collector,
                provider: providers[i],
                agreementCount: AGREEMENTS.getPairAgreementCount(collector, providers[i]),
                sumMaxNextClaim: AGREEMENTS.getSumMaxNextClaim(collector, providers[i]),
                escrowSnap: AGREEMENTS.getEscrowSnap(collector, providers[i]),
                escrow: AGREEMENTS.getEscrowAccount(collector, providers[i])
            });
        }
    }

    function _reconcilePair(IAgreementCollector collector, address provider) private returns (uint256 removed) {
        bytes16[] memory ids = this.getPairAgreements(collector, provider);
        for (uint256 i = 0; i < ids.length; ++i) {
            if (!MANAGER.reconcileAgreement(collector, ids[i])) ++removed;
        }
    }
}
