// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGraphTokenLock {
    enum Revocability {
        NotSet,
        Enabled,
        Disabled
    }

    // -- Balances --

    function currentBalance() external view returns (uint256);

    // -- Time & Periods --

    function currentTime() external view returns (uint256);

    function duration() external view returns (uint256);

    function sinceStartTime() external view returns (uint256);

    function amountPerPeriod() external view returns (uint256);

    function periodDuration() external view returns (uint256);

    function currentPeriod() external view returns (uint256);

    function passedPeriods() external view returns (uint256);

    // -- Locking & Release Schedule --

    function availableAmount() external view returns (uint256);

    function vestedAmount() external view returns (uint256);

    function releasableAmount() external view returns (uint256);

    function totalOutstandingAmount() external view returns (uint256);

    function surplusAmount() external view returns (uint256);

    // -- Value Transfer --

    function release() external;

    function withdrawSurplus(uint256 _amount) external;

    function revoke() external;
}
