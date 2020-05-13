pragma solidity 0.6.7;
pragma experimental "ABIEncoderV2";

import "./mixins/MixinChallengeRegistryCore.sol";
import "./mixins/MixinSetState.sol";
import "./mixins/MixinProgressState.sol";
import "./mixins/MixinSetAndProgressState.sol";
import "./mixins/MixinCancelDispute.sol";
import "./mixins/MixinSetOutcome.sol";


/// @dev Base contract implementing all logic needed for full-featured App registry
// solium-disable-next-line lbrace
contract ChallengeRegistry is
  MixinChallengeRegistryCore,
  MixinSetState,
  MixinProgressState,
  MixinSetAndProgressState,
  MixinCancelDispute,
  MixinSetOutcome {
    // solium-disable-next-line no-empty-blocks
    constructor () public {}
}
