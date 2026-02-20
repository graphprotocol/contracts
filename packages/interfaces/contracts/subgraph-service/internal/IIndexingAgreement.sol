// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.22;

import { IRecurringCollector } from "../../horizon/IRecurringCollector.sol";

/**
 * @title Interface for the {IndexingAgreement} library contract.
 * @author Edge & Node
 * @notice Interface for managing indexing agreement data and operations
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
interface IIndexingAgreement {
    /// @notice Versions of Indexing Agreement Metadata
    enum IndexingAgreementVersion {
        V1
    }

    /**
     * @notice Indexer Agreement Data
     * @param allocationId The allocation ID
     * @param version The indexing agreement version
     */
    struct State {
        address allocationId;
        IndexingAgreementVersion version;
    }

    /**
     * @notice Wrapper for Indexing Agreement and Collector Agreement Data
     * @param agreement The indexing agreement state
     * @param collectorAgreement The collector agreement data
     */
    struct AgreementWrapper {
        State agreement;
        IRecurringCollector.AgreementData collectorAgreement;
    }
}
