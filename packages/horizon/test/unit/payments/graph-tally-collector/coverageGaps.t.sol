// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IGraphTallyCollector } from "@graphprotocol/interfaces/contracts/horizon/IGraphTallyCollector.sol";

import { GraphTallyTest } from "./GraphTallyCollector.t.sol";

/// @notice Tests targeting uncovered view functions in GraphTallyCollector.sol
contract GraphTallyCollectorCoverageGapsTest is GraphTallyTest {
    /* solhint-disable graph/func-name-mixedcase */

    // ══════════════════════════════════════════════════════════════════════
    //  recoverRAVSigner (L90-91)
    // ══════════════════════════════════════════════════════════════════════

    function test_RecoverRAVSigner() public useGateway useSigner {
        uint128 tokens = 1000 ether;

        IGraphTallyCollector.ReceiptAggregateVoucher memory rav = IGraphTallyCollector.ReceiptAggregateVoucher({
            dataService: subgraphDataServiceAddress,
            serviceProvider: users.indexer,
            timestampNs: 0,
            valueAggregate: tokens,
            metadata: "",
            payer: users.gateway,
            collectionId: bytes32("test-collection")
        });

        bytes32 messageHash = graphTallyCollector.encodeRAV(rav);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        IGraphTallyCollector.SignedRAV memory signedRAV = IGraphTallyCollector.SignedRAV({
            rav: rav,
            signature: signature
        });

        address recovered = graphTallyCollector.recoverRAVSigner(signedRAV);
        assertEq(recovered, signer);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  authorizations view function (Authorizable L51, L54-55)
    // ══════════════════════════════════════════════════════════════════════

    function test_Authorizations_UnknownSigner() public {
        address unknown = makeAddr("unknown");
        (address authorizer, uint256 thawEndTimestamp, bool revoked) = graphTallyCollector.authorizations(unknown);
        assertEq(authorizer, address(0));
        assertEq(thawEndTimestamp, 0);
        assertFalse(revoked);
    }

    function test_Authorizations_KnownSigner() public useGateway useSigner {
        (address authorizer, uint256 thawEndTimestamp, bool revoked) = graphTallyCollector.authorizations(signer);
        assertEq(authorizer, users.gateway);
        assertEq(thawEndTimestamp, 0);
        assertFalse(revoked);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
