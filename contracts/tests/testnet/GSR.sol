pragma solidity ^0.6.4;

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
    uint256 public savingsRate; // savings rate being earned
    uint256 public reserves; // total of interest bearing GDAI
    uint256 public cumulativeInterestRate; // cumulative interest rate of the contract
    uint256 public lastDripTime; // Last time drip was called
    mapping(address => uint256) public balances; // balance of interest bearing GDAI
    GDAI public token; // GDAI

    event UpdateRate(uint256 newRate);
    event Drip(uint256 cumulativeInterestRate, uint256 lastDripTime);
    event Join(address indexed account, uint256 tokens);
    event Exit(address indexed account, uint256 tokens);

    /**
     * @dev Graph Saving Rate constructor.
     */
    constructor() public {
        Governed._initialize(msg.sender);
        cumulativeInterestRate = ISSUANCE_RATE_DECIMALS;
        savingsRate = ISSUANCE_RATE_DECIMALS;
        lastDripTime = now;
    }

    // Governance sets savings rate
    function setRatio(uint256 _newRate) external onlyGovernor {
        drip();
        savingsRate = _newRate;
        emit UpdateRate(savingsRate);
    }

    // Update the rate m and mint tokens
    // We enforce drip to always be called by all state changing functions. Lessens require statements
    function drip() public returns (uint256 updatedRate) {
        updatedRate = cumulativeInterestRate
            .mul(_pow(savingsRate, now - lastDripTime, ISSUANCE_RATE_DECIMALS))
            .div(ISSUANCE_RATE_DECIMALS);
        uint256 rateDifference = updatedRate.sub(cumulativeInterestRate);
        cumulativeInterestRate = updatedRate;
        lastDripTime = now;
        token.mint(address(this), reserves.mul(rateDifference));
        emit Drip(cumulativeInterestRate, lastDripTime);
    }

    // Someone enters
    function join(uint256 amount) external {
        drip();
        balances[msg.sender] = balances[msg.sender].add(amount);
        reserves = reserves.add(amount);
        token.transferFrom(msg.sender, address(this), cumulativeInterestRate.mul(amount));
        emit Join(msg.sender, amount);
    }

    // Someone exits
    function exit(uint256 amount) external {
        drip();
        balances[msg.sender] = balances[msg.sender].sub(amount);
        reserves = reserves.sub(amount);
        token.transfer(msg.sender, cumulativeInterestRate.mul(amount));
        emit Exit(msg.sender, amount);
    }

    /** TODO - have a math library and use it here and in RewardsMAnager
     * @dev Raises x to the power of n with scaling factor of base.
     * Based on: https://github.com/makerdao/dss/blob/master/src/pot.sol#L81
     * @param x Base of the exponentation
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
