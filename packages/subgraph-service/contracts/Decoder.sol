// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

contract Decoder {
    function decodeCollectIndexingFeeData(bytes calldata data) external pure returns (bytes16, bytes memory) {
        return abi.decode(data, (bytes16, bytes));
    }

    /**
     * @notice Decodes the RCA metadata.
     *
     * @param data The data to decode. See {ISubgraphService.AcceptIndexingAgreementMetadata}
     * @return The decoded data
     */
    function decodeRCAMetadata(
        bytes calldata data
    ) external pure returns (ISubgraphService.AcceptIndexingAgreementMetadata memory) {
        return abi.decode(data, (ISubgraphService.AcceptIndexingAgreementMetadata));
    }

    /**
     * @notice Decodes the RCAU metadata.
     *
     * @param data The data to decode. See {ISubgraphService.UpgradeIndexingAgreementMetadata}
     * @return The decoded data
     */
    function decodeRCAUMetadata(
        bytes calldata data
    ) external pure returns (ISubgraphService.UpgradeIndexingAgreementMetadata memory) {
        return abi.decode(data, (ISubgraphService.UpgradeIndexingAgreementMetadata));
    }

    /**
     * @notice Decodes the collect data for indexing fees V1.
     *
     * @param data The data to decode.
     */
    function decodeCollectIndexingFeeDataV1(
        bytes memory data
    ) external pure returns (uint256 entities, bytes32 poi, uint256 epoch) {
        return abi.decode(data, (uint256, bytes32, uint256));
    }

    /**
     * @notice Decodes the data for indexing agreement terms V1.
     *
     * @param data The data to decode. See {ISubgraphService.IndexingAgreementTermsV1}
     * @return The decoded data
     */
    function decodeIndexingAgreementTermsV1(
        bytes memory data
    ) external pure returns (ISubgraphService.IndexingAgreementTermsV1 memory) {
        return abi.decode(data, (ISubgraphService.IndexingAgreementTermsV1));
    }

    function _decodeCollectIndexingFeeData(bytes memory _data) internal view returns (bytes16, bytes memory) {
        try this.decodeCollectIndexingFeeData(_data) returns (bytes16 agreementId, bytes memory data) {
            return (agreementId, data);
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeCollectIndexingFeeData", _data);
        }
    }

    function _decodeRCAMetadata(
        bytes memory _data
    ) internal view returns (ISubgraphService.AcceptIndexingAgreementMetadata memory) {
        try this.decodeRCAMetadata(_data) returns (ISubgraphService.AcceptIndexingAgreementMetadata memory metadata) {
            return metadata;
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeRCAMetadata", _data);
        }
    }

    function _decodeRCAUMetadata(
        bytes memory _data
    ) internal view returns (ISubgraphService.UpgradeIndexingAgreementMetadata memory) {
        try this.decodeRCAUMetadata(_data) returns (ISubgraphService.UpgradeIndexingAgreementMetadata memory metadata) {
            return metadata;
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeRCAUMetadata", _data);
        }
    }

    function _decodeCollectIndexingFeeDataV1(bytes memory _data) internal view returns (uint256, bytes32, uint256) {
        try this.decodeCollectIndexingFeeDataV1(_data) returns (uint256 entities, bytes32 poi, uint256 epoch) {
            return (entities, poi, epoch);
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeCollectIndexingFeeDataV1", _data);
        }
    }

    function _decodeIndexingAgreementTermsV1(
        bytes memory _data
    ) internal view returns (ISubgraphService.IndexingAgreementTermsV1 memory) {
        try this.decodeIndexingAgreementTermsV1(_data) returns (
            ISubgraphService.IndexingAgreementTermsV1 memory terms
        ) {
            return terms;
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeCollectIndexingFeeData", _data);
        }
    }
}
