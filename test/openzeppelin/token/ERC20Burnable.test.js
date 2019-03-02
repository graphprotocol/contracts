const { BN, constants, expectEvent, shouldFail } = require('openzeppelin-test-helpers');
const { ZERO_ADDRESS } = constants;

const GraphToken = artifacts.require('GraphToken');

contract('ERC20Burnable', ([deploymentAddress, governor, targetAccount, ...otherAccounts]) => {
  const initialBalance = new BN(1000);

  beforeEach(async function () {
    this.token = await GraphToken.new(governor, initialBalance, { from: deploymentAddress });

    // mint some tokens for a target account to be burned by governor
    await this.token.mint(targetAccount, initialBalance, { from: governor })
  });

  shouldBehaveLikeERC20Burnable(targetAccount, initialBalance, governor);
});

function shouldBehaveLikeERC20Burnable (targetAccount, initialBalance, governor) {
  describe('burn', function () {
    describe('when the given amount is not greater than balance of the sender', function () {
      context('for a zero amount', function () {
        shouldBurn(new BN(0));
      });

      context('for a non-zero amount', function () {
        shouldBurn(new BN(100));
      });

      function shouldBurn (amount) {
        beforeEach(async function () {
          ({ logs: this.logs } = await this.token.burn(amount, { from: targetAccount }));
        });

        it('burns the requested amount', async function () {
          (await this.token.balanceOf(targetAccount)).should.be.bignumber.equal(initialBalance.sub(amount));
        });

        it('emits a transfer event', async function () {
          expectEvent.inLogs(this.logs, 'Transfer', {
            from: targetAccount,
            to: ZERO_ADDRESS,
            value: amount,
          });
        });
      }
    });

    describe('when the given amount is greater than the balance of the sender', function () {
      const amount = initialBalance.addn(1);

      it('reverts', async function () {
        await shouldFail.reverting(this.token.burn(amount, { from: targetAccount }));
      });
    });
  });

  describe('burnFrom', function () {
    describe('on success', function () {
      context('for a zero amount', function () {
        shouldBurnFrom(new BN(0));
      });

      context('for a non-zero amount', function () {
        shouldBurnFrom(new BN(100));
      });

      function shouldBurnFrom (amount) {
        const originalAllowance = amount.muln(3);

        beforeEach(async function () {
          await this.token.approve(governor, originalAllowance, { from: targetAccount });
          const { logs } = await this.token.burnFrom(targetAccount, amount, { from: governor });
          this.logs = logs;
        });

        it('burns the requested amount', async function () {
          (await this.token.balanceOf(targetAccount)).should.be.bignumber.equal(initialBalance.sub(amount));
        });

        it('decrements allowance', async function () {
          (await this.token.allowance(targetAccount, governor)).should.be.bignumber.equal(originalAllowance.sub(amount));
        });

        it('emits a transfer event', async function () {
          expectEvent.inLogs(this.logs, 'Transfer', {
            from: targetAccount,
            to: ZERO_ADDRESS,
            value: amount,
          });
        });
      }
    });

    describe('when the given amount is greater than the balance of the sender', function () {
      const amount = initialBalance.addn(1);

      it('reverts', async function () {
        await this.token.approve(governor, amount, { from: targetAccount });
        await shouldFail.reverting(this.token.burnFrom(targetAccount, amount, { from: governor }));
      });
    });

    describe('when the given amount is greater than the allowance', function () {
      const allowance = new BN(100);

      it('reverts', async function () {
        await this.token.approve(governor, allowance, { from: targetAccount });
        await shouldFail.reverting(this.token.burnFrom(targetAccount, allowance.addn(1), { from: governor }));
      });
    });
  });
}
