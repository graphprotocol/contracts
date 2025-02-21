// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { IAuthorizable } from "../../../../contracts/interfaces/IAuthorizable.sol";

import { GraphTallyTest } from "../GraphTallyCollector.t.sol";

contract GraphTallyCancelThawSignerTest is GraphTallyTest {
    /*
     * TESTS
     */

    function testGraphTally_CancelThawSigner() public useGateway useSigner {
        _thawSigner(signer);
        _cancelThawSigner(signer);
    }

    function testGraphTally_CancelThawSigner_RevertWhen_NotAuthorized() public useGateway {
        bytes memory expectedError = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotAuthorized.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.thawSigner(signer);
    }

    function testGraphTally_CancelThawSigner_RevertWhen_NotThawing() public useGateway useSigner {
        bytes memory expectedError = abi.encodeWithSelector(
            IAuthorizable.AuthorizableSignerNotThawing.selector,
            signer
        );
        vm.expectRevert(expectedError);
        graphTallyCollector.cancelThawSigner(signer);
    }
}
