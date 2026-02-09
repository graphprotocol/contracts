// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.33;

import { IndexingAgreement } from "./IndexingAgreement.sol";

library IndexingAgreementDecoderRaw {
    /**
     * @notice See {IndexingAgreementDecoder.decodeCollectIndexingFeeData}
     * @param data The data to decode
     * @return agreementId The agreement ID
     * @return nestedData The nested encoded data
     */
    function decodeCollectData(bytes calldata data) public pure returns (bytes16, bytes memory) {
        return abi.decode(data, (bytes16, bytes));
    }

    /**
     * @notice See {IndexingAgreementDecoder.decodeRCAMetadata}
     * @dev The data should be encoded as {IndexingAgreement.AcceptIndexingAgreementMetadata}
     * @param data The data to decode
     * @return The decoded data
     */
    function decodeRCAMetadata(
        bytes calldata data
    ) public pure returns (IndexingAgreement.AcceptIndexingAgreementMetadata memory) {
        return abi.decode(data, (IndexingAgreement.AcceptIndexingAgreementMetadata));
    }

    /**
     * @notice See {IndexingAgreementDecoder.decodeRCAUMetadata}
     * @dev The data should be encoded as {IndexingAgreement.UpdateIndexingAgreementMetadata}
     * @param data The data to decode
     * @return The decoded data
     */
    function decodeRCAUMetadata(
        bytes calldata data
    ) public pure returns (IndexingAgreement.UpdateIndexingAgreementMetadata memory) {
        return abi.decode(data, (IndexingAgreement.UpdateIndexingAgreementMetadata));
    }

    /**
     * @notice See {IndexingAgreementDecoder.decodeCollectIndexingFeeDataV1}
     * @dev The data should be encoded as (uint256 entities, bytes32 poi, uint256 epoch)
     * @param data The data to decode
     * @return The decoded collect indexing fee V1 data
     *
     */
    function decodeCollectIndexingFeeDataV1(
        bytes memory data
    ) public pure returns (IndexingAgreement.CollectIndexingFeeDataV1 memory) {
        return abi.decode(data, (IndexingAgreement.CollectIndexingFeeDataV1));
    }

    /**
     * @notice See {IndexingAgreementDecoder.decodeIndexingAgreementTermsV1}
     * @dev The data should be encoded as {IndexingAgreement.IndexingAgreementTermsV1}
     * @param data The data to decode
     * @return The decoded indexing agreement terms
     */
    function decodeIndexingAgreementTermsV1(
        bytes memory data
    ) public pure returns (IndexingAgreement.IndexingAgreementTermsV1 memory) {
        return abi.decode(data, (IndexingAgreement.IndexingAgreementTermsV1));
    }
}
