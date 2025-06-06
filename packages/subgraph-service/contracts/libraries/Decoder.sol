// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { UnsafeDecoder } from "./UnsafeDecoder.sol";
import { IndexingAgreement } from "./IndexingAgreement.sol";

library Decoder {
    /**
     * @notice Thrown when the data can't be decoded as expected
     * @param t The type of data that was expected
     * @param data The invalid data
     */
    error DecoderInvalidData(string t, bytes data);

    /**
     * @notice Decodes the data for collecting indexing fees.
     *
     * @param data The data to decode.
     * @return agreementId The agreement ID
     * @return nestedData The nested encoded data
     */
    function decodeCollectIndexingFeeData(bytes memory data) public pure returns (bytes16, bytes memory) {
        try UnsafeDecoder.decodeCollectIndexingFeeData_(data) returns (bytes16 agreementId, bytes memory nestedData) {
            return (agreementId, nestedData);
        } catch {
            revert DecoderInvalidData("decodeCollectIndexingFeeData", data);
        }
    }

    /**
     * @notice Decodes the RCA metadata.
     *
     * @param data The data to decode. See {IndexingAgreement.AcceptIndexingAgreementMetadata}
     * @return The decoded data
     */
    function decodeRCAMetadata(
        bytes memory data
    ) public pure returns (IndexingAgreement.AcceptIndexingAgreementMetadata memory) {
        try UnsafeDecoder.decodeRCAMetadata_(data) returns (
            IndexingAgreement.AcceptIndexingAgreementMetadata memory metadata
        ) {
            return metadata;
        } catch {
            revert DecoderInvalidData("decodeRCAMetadata", data);
        }
    }

    /**
     * @notice Decodes the RCAU metadata.
     *
     * @param data The data to decode. See {IndexingAgreement.UpdateIndexingAgreementMetadata}
     * @return The decoded data
     */
    function decodeRCAUMetadata(
        bytes memory data
    ) public pure returns (IndexingAgreement.UpdateIndexingAgreementMetadata memory) {
        try UnsafeDecoder.decodeRCAUMetadata_(data) returns (
            IndexingAgreement.UpdateIndexingAgreementMetadata memory metadata
        ) {
            return metadata;
        } catch {
            revert DecoderInvalidData("decodeRCAUMetadata", data);
        }
    }

    /**
     * @notice Decodes the collect data for indexing fees V1.
     *
     * @param data The data to decode.
     * @return entities The number of entities
     * @return poi The proof of indexing (POI)
     * @return epoch The epoch of the POI
     */
    function decodeCollectIndexingFeeDataV1(bytes memory data) public pure returns (uint256, bytes32, uint256) {
        try UnsafeDecoder.decodeCollectIndexingFeeDataV1_(data) returns (uint256 entities, bytes32 poi, uint256 epoch) {
            return (entities, poi, epoch);
        } catch {
            revert DecoderInvalidData("decodeCollectIndexingFeeDataV1", data);
        }
    }

    /**
     * @notice Decodes the data for indexing agreement terms V1.
     *
     * @param data The data to decode. See {IndexingAgreement.IndexingAgreementTermsV1}
     * @return The decoded data
     */
    function decodeIndexingAgreementTermsV1(
        bytes memory data
    ) public pure returns (IndexingAgreement.IndexingAgreementTermsV1 memory) {
        try UnsafeDecoder.decodeIndexingAgreementTermsV1_(data) returns (
            IndexingAgreement.IndexingAgreementTermsV1 memory terms
        ) {
            return terms;
        } catch {
            revert DecoderInvalidData("decodeCollectIndexingFeeData", data);
        }
    }
}
