// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.7.3;

import "../../governance/Governed.sol";
import "./GDAI.sol";

/**
 * @title Graph Saving Rate contract
 * Heavily influenced by Maker DAI savings rate
 * https://github.com/makerdao/dss/blob/master/src/pot.sol
 * @dev This contracts receives GDAI deposits and provides an interests rate for use in testnet.
 */

contract GSRManager is Governed {
    using SafeMath for uint256;

    uint256 private constant ISSUANCE_RATE_DECIMALS = 1e18;
    uint256 public savingsRate; // savings rate being earned (dsr in DSR)
    uint256 public reserves; // total interest bearing GDAI (Pie in DSR)
    uint256 public cumulativeInterestRate; // cumulative interest rate of the contract (chi in DSR)
    uint256 public lastDripTime; // Last time drip was called (rho in DSR)
    mapping(address => uint256) public balances; // balance of interest bearing GDAI (pie in DSR)
    GDAI public token; // GDAI

    event SetRate(uint256 newRate);
    event Drip(uint256 cumulativeInterestRate, uint256 lastDripTime);
    event Join(address indexed account, uint256 gdai, uint256 gsrBalance);
    event Exit(address indexed account, uint256 gsrBalance, uint256 gdai);

    /**
     * @dev Graph Saving Rate constructor.
     */
    constructor(uint256 _savingsRate, address _gdai) {
        require(_savingsRate != 0, "Savings rate can't be zero");
        Governed._initialize(msg.sender);
        cumulativeInterestRate = ISSUANCE_RATE_DECIMALS;
        lastDripTime = block.timestamp;
        savingsRate = _savingsRate;
        token = GDAI(_gdai);
    }

    // Governance sets savings rate
    function setRate(uint256 _newRate) external onlyGovernor {
        require(_newRate != 0, "Savings rate can't be zero");
        drip();
        savingsRate = _newRate;
        emit SetRate(savingsRate);
    }

    // Update the rate and mint tokens
    // We enforce drip to always be called by all state changing functions. Lessens require statements
    function drip() public returns (uint256 updatedRate) {
        updatedRate = calcUpdatedRate();
        uint256 rateDifference = updatedRate.sub(cumulativeInterestRate);
        cumulativeInterestRate = updatedRate;
        lastDripTime = block.timestamp;
        token.mint(address(this), reserves.mul(rateDifference).div(ISSUANCE_RATE_DECIMALS));
        emit Drip(cumulativeInterestRate, lastDripTime);
    }

    // Someone enters
    function join(uint256 _amount) external {
        drip();
        uint256 savingsBalance = _amount.mul(ISSUANCE_RATE_DECIMALS).div(cumulativeInterestRate);
        balances[msg.sender] = balances[msg.sender].add(savingsBalance);
        reserves = reserves.add(savingsBalance);
        token.transferFrom(msg.sender, address(this), _amount);
        emit Join(msg.sender, _amount, savingsBalance);
    }

    // Someone exits
    function exit(uint256 _amount) external {
        drip();
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        uint256 withdrawnAmount = _amount.mul(cumulativeInterestRate).div(ISSUANCE_RATE_DECIMALS);
        reserves = reserves.sub(_amount);
        token.transfer(msg.sender, withdrawnAmount);
        emit Exit(msg.sender, _amount, withdrawnAmount);
    }

    // Calculate the new cumulative interest rate
    function calcUpdatedRate() public view returns (uint256 updatedRate) {
        updatedRate = cumulativeInterestRate
            .mul(_pow(savingsRate, block.timestamp - lastDripTime, ISSUANCE_RATE_DECIMALS))
            .div(ISSUANCE_RATE_DECIMALS);
    }

    // Calculate the total balance a user would have if they withdrew
    function calcReturn(address _account) external view returns (uint256 totalBalance) {
        uint256 updatedRate = calcUpdatedRate();
        totalBalance = balances[_account].mul(updatedRate).div(ISSUANCE_RATE_DECIMALS);
    }

    /** TODO - have a math library and use it here and in RewardsMAnager
     * @dev Raises x to the power of n with scaling factor of base.
     * Based on: https://github.com/makerdao/dss/blob/master/src/pot.sol#L81
     * @param x Base of the exponentiation
     * @param n Exponent
     * @param base Scaling factor
     * @return z Exponential of n with base x
     */
    function _pow(
        uint256 x,
        uint256 n,
        uint256 base
    ) internal pure returns (uint256 z) {
        assembly {
            switch x
                case 0 {
                    switch n
                        case 0 {
                            z := base
                        }
                        default {
                            z := 0
                        }
                }
                default {
                    switch mod(n, 2)
                        case 0 {
                            z := base
                        }
                        default {
                            z := x
                        }
                    let half := div(base, 2) // for rounding.
                    for {
                        n := div(n, 2)
                    } n {
                        n := div(n, 2)
                    } {
                        let xx := mul(x, x)
                        if iszero(eq(div(xx, x), x)) {
                            revert(0, 0)
                        }
                        let xxRound := add(xx, half)
                        if lt(xxRound, xx) {
                            revert(0, 0)
                        }
                        x := div(xxRound, base)
                        if mod(n, 2) {
                            let zx := mul(z, x)
                            if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                                revert(0, 0)
                            }
                            let zxRound := add(zx, half)
                            if lt(zxRound, zx) {
                                revert(0, 0)
                            }
                            z := div(zxRound, base)
                        }
                    }
                }
        }
    }
}
