// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { ITAPCollector } from "../../../../contracts/interfaces/ITAPCollector.sol";

import { TAPCollectorTest } from "../TAPCollector.t.sol";

contract TAPCollectorThawSignerTest is TAPCollectorTest {

    /*
     * TESTS
     */

    function testTAPCollector_ThawSigner() public useGateway useSigner {
        _thawSigner(signer);
    }

    function testTAPCollector_ThawSigner_RevertWhen_NotAuthorized() public useGateway {
        bytes memory expectedError = abi.encodeWithSelector(
            ITAPCollector.TAPCollectorSignerNotAuthorizedByPayer.selector,
            users.gateway,
            signer
        );
        vm.expectRevert(expectedError);
        tapCollector.thawSigner(signer);
    }
}
