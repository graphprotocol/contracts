// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { IndexingAgreement } from "../../../contracts/libraries/IndexingAgreement.sol";

contract IndexingAgreementTest is Test {
    function test_StorageManagerLocation() public pure {
        assertEq(
            IndexingAgreement.INDEXING_AGREEMENT_STORAGE_MANAGER_LOCATION,
            keccak256(
                abi.encode(
                    uint256(keccak256("graphprotocol.subgraph-service.storage.StorageManager.IndexingAgreement")) - 1
                )
            ) & ~bytes32(uint256(0xff))
        );
    }
}
