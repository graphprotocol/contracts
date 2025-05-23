// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IndexingAgreement } from "./IndexingAgreement.sol";

library UnsafeDecoder {
    /**
     * @notice See {Decoder.decodeCollectIndexingFeeData}
     */
    function decodeCollectIndexingFeeData_(bytes calldata data) public pure returns (bytes16, bytes memory) {
        return abi.decode(data, (bytes16, bytes));
    }

    /**
     * @notice See {Decoder.decodeRCAMetadata}
     */
    function decodeRCAMetadata_(
        bytes calldata data
    ) public pure returns (IndexingAgreement.AcceptIndexingAgreementMetadata memory) {
        return abi.decode(data, (IndexingAgreement.AcceptIndexingAgreementMetadata));
    }

    /**
     * @notice See {Decoder.decodeRCAUMetadata}
     */
    function decodeRCAUMetadata_(
        bytes calldata data
    ) public pure returns (IndexingAgreement.UpdateIndexingAgreementMetadata memory) {
        return abi.decode(data, (IndexingAgreement.UpdateIndexingAgreementMetadata));
    }

    /**
     * @notice See {Decoder.decodeCollectIndexingFeeDataV1}
     */
    function decodeCollectIndexingFeeDataV1_(
        bytes memory data
    ) public pure returns (uint256 entities, bytes32 poi, uint256 epoch) {
        return abi.decode(data, (uint256, bytes32, uint256));
    }

    /**
     * @notice See {Decoder.decodeIndexingAgreementTermsV1}
     */
    function decodeIndexingAgreementTermsV1_(
        bytes memory data
    ) public pure returns (IndexingAgreement.IndexingAgreementTermsV1 memory) {
        return abi.decode(data, (IndexingAgreement.IndexingAgreementTermsV1));
    }
}
