const web3 = require('web3')
const BN = web3.utils.BN

module.exports = {
  curation: {
    // Reserve ratio to set bonding curve for curation (in PPM)
    reserveRatio: new BN('500000'),
    // Minimum amount required to be staked by Curators
    minimumCurationStake: web3.utils.toWei(new BN('100')),
  },
  dispute: {
    minimumDeposit: web3.utils.toWei(new BN('100')),
    rewardPercentage: new BN(1000), // in basis points
    slashingPercentage: new BN(1000), // in basis points
  },
  epochs: {
    lengthInBlocks: new BN((24 * 60 * 60) / 15), // One day in blocks
  },
  staking: {
    channelHub: '0x4b8e4A4335CE274DA2B44FBF7a4502b3cB0AcA57',
    maxSettlementDuration: 5, // in epochs
    thawingPeriod: 20, // in blocks
  },
  token: {
    initialSupply: web3.utils.toWei(new BN('10000000')),
  },
}
