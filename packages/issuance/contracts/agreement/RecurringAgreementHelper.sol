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
    /// @notice The RecurringAgreementManager contract address
    address public immutable MANAGER;

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
        MANAGER = manager;
        GRAPH_TOKEN = graphToken;
    }

    // -- Audit Views --

    /// @inheritdoc IRecurringAgreementHelper
    function auditGlobal() external view returns (GlobalAudit memory audit) {
        IRecurringAgreements mgr = IRecurringAgreements(MANAGER);
        audit = GlobalAudit({
            tokenBalance: GRAPH_TOKEN.balanceOf(MANAGER),
            sumMaxNextClaimAll: mgr.getSumMaxNextClaimAll(),
            totalEscrowDeficit: mgr.getTotalEscrowDeficit(),
            escrowBasis: mgr.getEscrowBasis(),
            minOnDemandBasisThreshold: mgr.getMinOnDemandBasisThreshold(),
            minFullBasisMargin: mgr.getMinFullBasisMargin(),
            collectorCount: mgr.getCollectorCount()
        });
    }

    /// @inheritdoc IRecurringAgreementHelper
    function auditPairs(address collector) external view returns (PairAudit[] memory pairs) {
        return _auditPairs(collector, 0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function auditPairs(
        address collector,
        uint256 offset,
        uint256 count
    ) external view returns (PairAudit[] memory pairs) {
        return _auditPairs(collector, offset, count);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function auditPair(address collector, address provider) external view returns (PairAudit memory pair) {
        IRecurringAgreements mgr = IRecurringAgreements(MANAGER);
        pair = PairAudit({
            collector: collector,
            provider: provider,
            agreementCount: mgr.getPairAgreementCount(collector, provider),
            sumMaxNextClaim: mgr.getSumMaxNextClaim(IAgreementCollector(collector), provider),
            escrowSnap: mgr.getEscrowSnap(collector, provider),
            escrow: mgr.getEscrowAccount(IAgreementCollector(collector), provider)
        });
    }

    // -- Enumeration Views --

    /// @inheritdoc IRecurringAgreementHelper
    function getPairAgreements(address collector, address provider) external view returns (bytes16[] memory) {
        return getPairAgreements(collector, provider, 0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getPairAgreements(
        address collector,
        address provider,
        uint256 offset,
        uint256 count
    ) public view returns (bytes16[] memory result) {
        IRecurringAgreements mgr = IRecurringAgreements(MANAGER);
        uint256 total = mgr.getPairAgreementCount(collector, provider);
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new bytes16[](0);
        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;
        result = new bytes16[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = mgr.getPairAgreementAt(collector, provider, offset + i);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getCollectors() external view returns (address[] memory) {
        return getCollectors(0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getCollectors(uint256 offset, uint256 count) public view returns (address[] memory result) {
        IRecurringAgreements mgr = IRecurringAgreements(MANAGER);
        uint256 total = mgr.getCollectorCount();
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new address[](0);
        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;
        result = new address[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = mgr.getCollectorAt(offset + i);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getProviders(address collector) external view returns (address[] memory) {
        return getProviders(collector, 0, type(uint256).max);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function getProviders(
        address collector,
        uint256 offset,
        uint256 count
    ) public view returns (address[] memory result) {
        IRecurringAgreements mgr = IRecurringAgreements(MANAGER);
        uint256 total = mgr.getProviderCount(collector);
        // solhint-disable-next-line gas-strict-inequalities
        if (total <= offset) return new address[](0);
        uint256 remaining = total - offset;
        if (remaining < count) count = remaining;
        result = new address[](count);
        for (uint256 i = 0; i < count; ++i) result[i] = mgr.getProviderAt(collector, offset + i);
    }

    // -- Reconciliation Discovery --

    /// @inheritdoc IRecurringAgreementHelper
    function checkPairStaleness(
        address collector,
        address provider
    ) external view returns (AgreementStaleness[] memory staleAgreements, bool escrowStale) {
        IRecurringAgreements mgr = IRecurringAgreements(MANAGER);
        uint256 count = mgr.getPairAgreementCount(collector, provider);
        staleAgreements = new AgreementStaleness[](count);
        for (uint256 i = 0; i < count; ++i) {
            bytes16 id = mgr.getPairAgreementAt(collector, provider, i);
            uint256 cached = mgr.getAgreementMaxNextClaim(collector, id);
            uint256 live = IAgreementCollector(collector).getMaxNextClaim(id);
            staleAgreements[i] = AgreementStaleness({
                agreementId: id,
                cachedMaxNextClaim: cached,
                liveMaxNextClaim: live,
                stale: cached != live
            });
        }
        escrowStale =
            mgr.getEscrowSnap(collector, provider) !=
            mgr.getEscrowAccount(IAgreementCollector(collector), provider).balance;
    }

    // -- Reconciliation --

    /// @inheritdoc IRecurringAgreementHelper
    function reconcilePair(address collector, address provider) external returns (uint256 removed, bool pairExists) {
        removed = _reconcilePair(collector, provider);
        pairExists = IRecurringAgreementManagement(MANAGER).reconcileProvider(collector, provider);
    }

    /// @inheritdoc IRecurringAgreementHelper
    function reconcileCollector(address collector) external returns (uint256 removed, bool collectorExists) {
        IRecurringAgreementManagement mgt = IRecurringAgreementManagement(MANAGER);
        // Snapshot providers before iterating (removal modifies the set)
        address[] memory providers = this.getProviders(collector);
        for (uint256 p = 0; p < providers.length; ++p) {
            removed += _reconcilePair(collector, providers[p]);
            mgt.reconcileProvider(collector, providers[p]);
        }
        collectorExists = IRecurringAgreements(MANAGER).getProviderCount(collector) != 0;
    }

    /// @inheritdoc IRecurringAgreementHelper
    function reconcileAll() external returns (uint256 removed) {
        IRecurringAgreementManagement mgt = IRecurringAgreementManagement(MANAGER);
        // Snapshot collectors before iterating
        address[] memory collectors = this.getCollectors();
        for (uint256 c = 0; c < collectors.length; ++c) {
            address[] memory providers = this.getProviders(collectors[c]);
            for (uint256 p = 0; p < providers.length; ++p) {
                removed += _reconcilePair(collectors[c], providers[p]);
                mgt.reconcileProvider(collectors[c], providers[p]);
            }
        }
    }

    // -- Private Helpers --

    function _auditPairs(
        address collector,
        uint256 offset,
        uint256 count
    ) private view returns (PairAudit[] memory pairs) {
        IRecurringAgreements mgr = IRecurringAgreements(MANAGER);
        address[] memory providers = this.getProviders(collector, offset, count);
        pairs = new PairAudit[](providers.length);
        for (uint256 i = 0; i < providers.length; ++i) {
            pairs[i] = PairAudit({
                collector: collector,
                provider: providers[i],
                agreementCount: mgr.getPairAgreementCount(collector, providers[i]),
                sumMaxNextClaim: mgr.getSumMaxNextClaim(IAgreementCollector(collector), providers[i]),
                escrowSnap: mgr.getEscrowSnap(collector, providers[i]),
                escrow: mgr.getEscrowAccount(IAgreementCollector(collector), providers[i])
            });
        }
    }

    function _reconcilePair(address collector, address provider) private returns (uint256 removed) {
        IRecurringAgreementManagement mgt = IRecurringAgreementManagement(MANAGER);
        bytes16[] memory ids = this.getPairAgreements(collector, provider);
        for (uint256 i = 0; i < ids.length; ++i) {
            if (!mgt.reconcileAgreement(collector, ids[i])) ++removed;
        }
    }
}
