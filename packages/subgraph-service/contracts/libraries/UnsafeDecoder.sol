// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IndexingAgreement } from "./IndexingAgreement.sol";

library UnsafeDecoder {
    /**
     * @notice See {Decoder.decodeCollectIndexingFeeData}
     * @param data The data to decode
     * @return agreementId The agreement ID
     * @return nestedData The nested encoded data
     */
    function decodeCollectIndexingFeeData_(bytes calldata data) public pure returns (bytes16, bytes memory) {
        return abi.decode(data, (bytes16, bytes));
    }

    /**
     * @notice See {Decoder.decodeRCAMetadata}
     * @dev The data should be encoded as {IndexingAgreement.AcceptIndexingAgreementMetadata}
     * @param data The data to decode
     * @return The decoded data
     *
     */
    function decodeRCAMetadata_(
        bytes calldata data
    ) public pure returns (IndexingAgreement.AcceptIndexingAgreementMetadata memory) {
        return abi.decode(data, (IndexingAgreement.AcceptIndexingAgreementMetadata));
    }

    /**
     * @notice See {Decoder.decodeRCAUMetadata}
     * @dev The data should be encoded as {IndexingAgreement.UpdateIndexingAgreementMetadata}
     * @param data The data to decode
     * @return The decoded data
     */
    function decodeRCAUMetadata_(
        bytes calldata data
    ) public pure returns (IndexingAgreement.UpdateIndexingAgreementMetadata memory) {
        return abi.decode(data, (IndexingAgreement.UpdateIndexingAgreementMetadata));
    }

    /**
     * @notice See {Decoder.decodeCollectIndexingFeeDataV1}
     * @dev The data should be encoded as (uint256 entities, bytes32 poi, uint256 epoch)
     * @param data The data to decode
     * @return entities The number of entities indexed
     * @return poi The proof of indexing
     * @return epoch The current epoch
     */
    function decodeCollectIndexingFeeDataV1_(
        bytes memory data
    ) public pure returns (uint256 entities, bytes32 poi, uint256 epoch) {
        return abi.decode(data, (uint256, bytes32, uint256));
    }

    /**
     * @notice See {Decoder.decodeIndexingAgreementTermsV1}
     * @dev The data should be encoded as {IndexingAgreement.IndexingAgreementTermsV1}
     * @param data The data to decode
     * @return The decoded indexing agreement terms
     */
    function decodeIndexingAgreementTermsV1_(
        bytes memory data
    ) public pure returns (IndexingAgreement.IndexingAgreementTermsV1 memory) {
        return abi.decode(data, (IndexingAgreement.IndexingAgreementTermsV1));
    }
}
