// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.33;

import { IndexingAgreementDecoderRaw } from "./IndexingAgreementDecoderRaw.sol";
import { IndexingAgreement } from "./IndexingAgreement.sol";

/**
 * @title IndexingAgreementDecoder library
 * @author Edge & Node
 * @notice Safe decoder for indexing agreement data structures, reverting with typed errors on malformed input.
 */
library IndexingAgreementDecoder {
    /**
     * @notice Thrown when the data can't be decoded as expected
     * @param t The type of data that was expected
     * @param data The invalid data
     */
    error IndexingAgreementDecoderInvalidData(string t, bytes data);

    /**
     * @notice Decodes the data for collecting indexing fees.
     *
     * @param data The data to decode.
     * @return agreementId The agreement ID
     * @return nestedData The nested encoded data
     */
    function decodeCollectData(bytes memory data) public pure returns (bytes16, bytes memory) {
        try IndexingAgreementDecoderRaw.decodeCollectData(data) returns (bytes16 agreementId, bytes memory nestedData) {
            return (agreementId, nestedData);
        } catch {
            revert IndexingAgreementDecoderInvalidData("decodeCollectData", data);
        }
    }

    /**
     * @notice Decodes the RCA metadata.
     *
     * @param data The data to decode.
     * @return The decoded data. See {IndexingAgreement.AcceptIndexingAgreementMetadata}
     */
    function decodeRCAMetadata(
        bytes memory data
    ) public pure returns (IndexingAgreement.AcceptIndexingAgreementMetadata memory) {
        try IndexingAgreementDecoderRaw.decodeRCAMetadata(data) returns (
            IndexingAgreement.AcceptIndexingAgreementMetadata memory decoded
        ) {
            return decoded;
        } catch {
            revert IndexingAgreementDecoderInvalidData("decodeRCAMetadata", data);
        }
    }

    /**
     * @notice Decodes the RCAU metadata.
     *
     * @param data The data to decode.
     * @return The decoded data. See {IndexingAgreement.UpdateIndexingAgreementMetadata}
     */
    function decodeRCAUMetadata(
        bytes memory data
    ) public pure returns (IndexingAgreement.UpdateIndexingAgreementMetadata memory) {
        try IndexingAgreementDecoderRaw.decodeRCAUMetadata(data) returns (
            IndexingAgreement.UpdateIndexingAgreementMetadata memory decoded
        ) {
            return decoded;
        } catch {
            revert IndexingAgreementDecoderInvalidData("decodeRCAUMetadata", data);
        }
    }

    /**
     * @notice Decodes the collect data for indexing fees V1.
     *
     * @param data The data to decode.
     * @return The decoded data structure. See {IndexingAgreement.CollectIndexingFeeDataV1}
     */
    function decodeCollectIndexingFeeDataV1(
        bytes memory data
    ) public pure returns (IndexingAgreement.CollectIndexingFeeDataV1 memory) {
        try IndexingAgreementDecoderRaw.decodeCollectIndexingFeeDataV1(data) returns (
            IndexingAgreement.CollectIndexingFeeDataV1 memory decoded
        ) {
            return decoded;
        } catch {
            revert IndexingAgreementDecoderInvalidData("decodeCollectIndexingFeeDataV1", data);
        }
    }

    /**
     * @notice Decodes the data for indexing agreement terms V1.
     *
     * @param data The data to decode.
     * @return The decoded data structure. See {IndexingAgreement.IndexingAgreementTermsV1}
     */
    function decodeIndexingAgreementTermsV1(
        bytes memory data
    ) public pure returns (IndexingAgreement.IndexingAgreementTermsV1 memory) {
        try IndexingAgreementDecoderRaw.decodeIndexingAgreementTermsV1(data) returns (
            IndexingAgreement.IndexingAgreementTermsV1 memory decoded
        ) {
            return decoded;
        } catch {
            revert IndexingAgreementDecoderInvalidData("decodeIndexingAgreementTermsV1", data);
        }
    }
}
