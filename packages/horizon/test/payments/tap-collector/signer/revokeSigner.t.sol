// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ITAPCollector } from "../../../../contracts/interfaces/ITAPCollector.sol";

import { TAPCollectorTest } from "../TAPCollector.t.sol";

contract TAPCollectorRevokeAuthorizedSignerTest is TAPCollectorTest {

    /*
     * TESTS
     */

    function testTAPCollector_RevokeAuthorizedSigner() public useGateway useSigner {
        _thawSigner(signer);

        // Advance time to thaw signer
        skip(revokeSignerThawingPeriod + 1);

        _revokeAuthorizedSigner(signer);
    }

    function testTAPCollector_RevokeAuthorizedSigner_RevertWhen_NotAuthorized() public useGateway {
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerNotAuthorizedByPayer.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.revokeAuthorizedSigner(signer);
    }
    
    function testTAPCollector_RevokeAuthorizedSigner_RevertWhen_NotThawing() public useGateway useSigner {
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerNotThawing.selector,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.revokeAuthorizedSigner(signer);
    }

    function testTAPCollector_RevokeAuthorizedSigner_RevertWhen_StillThawing() public useGateway useSigner {
        _thawSigner(signer);
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerStillThawing.selector,
            block.timestamp,
            block.timestamp + revokeSignerThawingPeriod
        );
        vm.expectRevert(expectedError);
        tapCollector.revokeAuthorizedSigner(signer);
    }
}
