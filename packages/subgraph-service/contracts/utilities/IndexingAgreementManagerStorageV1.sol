// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IndexingAgreement } from "../libraries/IndexingAgreement.sol";

abstract contract IndexingAgreementManagerStorageV1 {
    IndexingAgreement.Manager internal _indexingAgreementManager;
}
