// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ITAPCollector } from "../../../../contracts/interfaces/ITAPCollector.sol";

import { TAPCollectorTest } from "../TAPCollector.t.sol";

contract TAPCollectorCancelThawSignerTest is TAPCollectorTest {

    /*
     * TESTS
     */

    function testTAPCollector_CancelThawSigner() public useGateway useSigner {
        _thawSigner(signer);
        _cancelThawSigner(signer);
    }

    function testTAPCollector_CancelThawSigner_RevertWhen_NotAuthorized() public useGateway {
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerNotAuthorizedByPayer.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.thawSigner(signer);
    }
    
    function testTAPCollector_CancelThawSigner_RevertWhen_NotThawing() public useGateway useSigner {
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerNotThawing.selector,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.cancelThawSigner(signer);
    }
}
