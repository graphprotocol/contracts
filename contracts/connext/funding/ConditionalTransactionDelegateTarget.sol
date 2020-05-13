pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "./state-deposit-holders/MultisigTransfer.sol";
import "../adjudicator/ChallengeRegistry.sol";
import "./libs/LibOutcome.sol";


/// @title ConditionalTransactionDelegateTarget
/// @author Liam Horne - <liam@l4v.io>
contract ConditionalTransactionDelegateTarget is MultisigTransfer {

    uint256 constant MAX_UINT256 = 2 ** 256 - 1;

    struct FreeBalanceAppState {
        address[] tokenAddresses;
        // The inner array contains the list of CoinTransfers for a single asset type
        // The outer array contains the list of asset balances for respecitve assets
        // according to the indexing used in the `tokens` array above
        LibOutcome.CoinTransfer[][] balances;
        bytes32[] activeApps;
    }

    struct MultiAssetMultiPartyCoinTransferInterpreterParams {
        uint256[] limit;
        address[] tokenAddresses;
    }

    function withdrawWrapper(
        address payable recipient,
        address assetId,
        uint256 amount,
        bytes32 /* nonce */
    )
        public
    {
        multisigTransfer(recipient, assetId, amount);
    }

    function executeEffectOfFreeBalance(
        ChallengeRegistry challengeRegistry,
        bytes32 freeBalanceAppIdentityHash,
        address multiAssetMultiPartyCoinTransferInterpreterAddress
    )
        public
    {
        FreeBalanceAppState memory freeBalanceAppState = abi.decode(
            challengeRegistry.getOutcome(freeBalanceAppIdentityHash),
            (FreeBalanceAppState)
        );

        uint256[] memory limits = new uint256[](
            freeBalanceAppState.tokenAddresses.length
        );

        for (uint256 i = 0; i < freeBalanceAppState.tokenAddresses.length; i++) {
            // The transaction's interpreter parameters are determined at the time
            // of creation of the free balance; hence we cannot know how much will be
            // deposited into it all-time. Relying on the app state is unsafe so
            // we just give it full permissions by setting the limit to the max here.
            limits[i] = MAX_UINT256;
        }

        (bool success, ) = multiAssetMultiPartyCoinTransferInterpreterAddress.delegatecall(
            abi.encodeWithSignature(
                "interpretOutcomeAndExecuteEffect(bytes,bytes)",
                abi.encode(freeBalanceAppState.balances),
                abi.encode(
                    MultiAssetMultiPartyCoinTransferInterpreterParams(
                        limits,
                        freeBalanceAppState.tokenAddresses
                    )
                )
            )
        );

        require(
            success,
            "Execution of executeEffectOfFreeBalance failed"
        );
    }

    /// @notice Execute a fund transfer for a state channel app in a finalized state
    /// @param appIdentityHash AppIdentityHash to be resolved
    function executeEffectOfInterpretedAppOutcome(
        ChallengeRegistry challengeRegistry,
        bytes32 freeBalanceAppIdentityHash,
        bytes32 appIdentityHash,
        address interpreterAddress,
        bytes memory interpreterParams
    )
        public
    {
        bytes32[] memory activeApps = abi.decode(
            challengeRegistry.getOutcome(freeBalanceAppIdentityHash),
            (FreeBalanceAppState)
        ).activeApps;

        bool appIsFunded = false;

        for (uint256 i = 0; i < activeApps.length; i++) {
            if (activeApps[i] == appIdentityHash) {
                appIsFunded = true;
            }
        }

        require(appIsFunded, "Referenced AppInstance is not funded");

        bytes memory outcome = challengeRegistry.getOutcome(appIdentityHash);

        (bool success, ) = interpreterAddress.delegatecall(
            abi.encodeWithSignature(
                "interpretOutcomeAndExecuteEffect(bytes,bytes)",
                outcome,
                interpreterParams
            )
        );

        require(
            success,
            "Execution of executeEffectOfInterpretedAppOutcome failed"
        );
    }
}
