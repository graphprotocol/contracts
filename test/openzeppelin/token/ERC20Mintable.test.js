const { BN, constants, expectEvent, shouldFail } = require('openzeppelin-test-helpers');
const { ZERO_ADDRESS } = constants;

const GraphToken = artifacts.require('GraphToken');

let deploymentAddress

contract('ERC20Mintable', function ([deploymentAccount, governor, otherMinter, ...otherAccounts]) {
  deploymentAddress = deploymentAccount

  const initialBalance = new BN(1000);

  beforeEach(async function () {
    this.token = await GraphToken.new(governor, initialBalance, { from: deploymentAddress });
  });

  describe('minter role', function () {
    beforeEach(async function () {
      this.contract = this.token;
      await this.contract.addMinter(otherMinter, { from: governor });
    });

    shouldBehaveLikePublicRole(governor, otherMinter, otherAccounts, 'minter');
  });

  shouldBehaveLikeERC20Mintable(governor, otherAccounts);
});

function capitalize (str) {
  return str.replace(/\b\w/g, l => l.toUpperCase());
}

// Tests that a role complies with the standard role interface, that is:
//  * an onlyRole modifier
//  * an isRole function
//  * an addRole function, accessible to role havers
//  * a renounceRole function
//  * roleAdded and roleRemoved events
// Both the modifier and an additional internal remove function are tested through a mock contract that exposes them.
// This mock contract should be stored in this.contract.
//
// @param authorized an account that has the role
// @param otherAuthorized another account that also has the role
// @param anyone an account that doesn't have the role, passed inside an array for ergonomics
// @param rolename a string with the name of the role
// @param manager undefined for regular roles, or a manager account for managed roles. In these, only the manager
// account can create and remove new role bearers.
function shouldBehaveLikePublicRole (authorized, otherAuthorized, [anyone], rolename, manager) {
  rolename = capitalize(rolename);

  describe('should behave like public role', function () {
    beforeEach('check preconditions', async function () {
      (await this.contract[`is${rolename}`](authorized)).should.equal(true);
      (await this.contract[`is${rolename}`](otherAuthorized)).should.equal(true);
      (await this.contract[`is${rolename}`](anyone)).should.equal(false);
    });

    if (manager === undefined) { // Managed roles are only assigned by the manager, and none are set at construction
      /**
       * @dev The deployment address is the initial minter and then removed after the `governor` is added
       */
      it('emits events during construction', async function () {
        await expectEvent.inConstruction(this.contract, `${rolename}Added`, {
          account: deploymentAddress,
        });
      });
    }

    it('reverts when querying roles for the null account', async function () {
      await shouldFail.reverting(this.contract[`is${rolename}`](ZERO_ADDRESS));
    });

    /**
     * @dev The `onlyMinter` modifier is not found
     * @todo Solve this!
     * @see https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/mocks/MinterRoleMock.sol
     */
    describe('access control', function () {
      context('from authorized account', function () {
        const to = anyone
        const from = authorized;

        it('allows access', async function () {
          await this.contract.mint(to, 1, { from })
        });
      });

      context('from unauthorized account', function () {
        const to = authorized
        const from = anyone;

        it('reverts', async function () {
          await shouldFail.reverting(this.contract.mint(to, 1, { from }))
        });
      });
    });

    describe('add', function () {
      const from = manager === undefined ? authorized : manager;

      context(`from ${manager ? 'the manager' : 'a role-haver'} account`, function () {
        it('adds role to a new account', async function () {
          await this.contract[`add${rolename}`](anyone, { from });
          (await this.contract[`is${rolename}`](anyone)).should.equal(true);
        });

        it(`emits a ${rolename}Added event`, async function () {
          const { logs } = await this.contract[`add${rolename}`](anyone, { from });
          expectEvent.inLogs(logs, `${rolename}Added`, { account: anyone });
        });

        it('reverts when adding role to an already assigned account', async function () {
          await shouldFail.reverting(this.contract[`add${rolename}`](authorized, { from }));
        });

        it('reverts when adding role to the null account', async function () {
          await shouldFail.reverting(this.contract[`add${rolename}`](ZERO_ADDRESS, { from }));
        });
      });
    });

    /**
     * @dev The `_removeMinter` function is `internal` and is not accessable without a mock contract
     * @see https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/mocks/MinterRoleMock.sol
     * @todo Expose the function or remove the test
     */
    // describe('remove', function () {
    //   // Non-managed roles have no restrictions on the mocked '_remove' function (exposed via 'remove').
    //   const from = manager || anyone;

    //   context(`from ${manager ? 'the manager' : 'any'} account`, function () {
    //     it('removes role from an already assigned account', async function () {
    //       await this.contract[`_remove${rolename}`](authorized, { from });
    //       (await this.contract[`is${rolename}`](authorized)).should.equal(false);
    //       (await this.contract[`is${rolename}`](otherAuthorized)).should.equal(true);
    //     });

    //     it(`emits a ${rolename}Removed event`, async function () {
    //       const { logs } = await this.contract[`_remove${rolename}`](authorized, { from });
    //       expectEvent.inLogs(logs, `${rolename}Removed`, { account: authorized });
    //     });

    //     it('reverts when removing from an unassigned account', async function () {
    //       await shouldFail.reverting(this.contract[`_remove${rolename}`](anyone), { from });
    //     });

    //     it('reverts when removing role from the null account', async function () {
    //       await shouldFail.reverting(this.contract[`_remove${rolename}`](ZERO_ADDRESS), { from });
    //     });
    //   });
    // });

    describe('renouncing roles', function () {
      it('renounces an assigned role', async function () {
        await this.contract[`renounce${rolename}`]({ from: authorized });
        (await this.contract[`is${rolename}`](authorized)).should.equal(false);
      });

      it(`emits a ${rolename}Removed event`, async function () {
        const { logs } = await this.contract[`renounce${rolename}`]({ from: authorized });
        expectEvent.inLogs(logs, `${rolename}Removed`, { account: authorized });
      });

      it('reverts when renouncing unassigned role', async function () {
        await shouldFail.reverting(this.contract[`renounce${rolename}`]({ from: anyone }));
      });
    });
  });
}

function shouldBehaveLikeERC20Mintable (minter, [anyone]) {
    describe('as a mintable token', function () {
      describe('mint', function () {
        const amount = new BN(100);
  
        context('when the sender has minting permission', function () {
          const from = minter;
  
          context('for a zero amount', function () {
            shouldMint(new BN(0));
          });
  
          context('for a non-zero amount', function () {
            shouldMint(amount);
          });
  
          function shouldMint (amount) {
            beforeEach(async function () {
              ({ logs: this.logs } = await this.token.mint(anyone, amount, { from }));
            });
  
            it('mints the requested amount', async function () {
              (await this.token.balanceOf(anyone)).should.be.bignumber.equal(amount);
            });
  
            it('emits a mint and a transfer event', async function () {
              expectEvent.inLogs(this.logs, 'Transfer', {
                from: ZERO_ADDRESS,
                to: anyone,
                value: amount,
              });
            });
          }
        });
  
        context('when the sender doesn\'t have minting permission', function () {
          const from = anyone;
  
          it('reverts', async function () {
            await shouldFail.reverting(this.token.mint(anyone, amount, { from }));
          });
        });
      });
    });
  }
