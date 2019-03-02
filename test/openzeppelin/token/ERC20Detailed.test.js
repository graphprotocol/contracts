const { BN } = require('openzeppelin-test-helpers');

const GraphToken = artifacts.require('GraphToken');

contract('ERC20Detailed', accounts => {
  const _name = 'Graph Token';
  const _symbol = 'GRT';
  const _decimals = new BN(18);

  const initialSupply = new BN(100),
    initialHolder = accounts[1]; // using accounts[0] for the deployer throws an error

  beforeEach(async function () {
    this.detailedERC20 = await GraphToken.new(initialHolder, initialSupply.toNumber())
  });

  it('has a name', async function () {
    (await this.detailedERC20.name()).should.be.equal(_name);
  });

  it('has a symbol', async function () {
    (await this.detailedERC20.symbol()).should.be.equal(_symbol);
  });

  it('has an amount of decimals', async function () {
    (await this.detailedERC20.decimals()).should.be.bignumber.equal(_decimals);
  });
});