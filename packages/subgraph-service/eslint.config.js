// @ts-check
/* eslint-disable no-undef */
/* eslint-disable @typescript-eslint/no-var-requires */
/* eslint-disable @typescript-eslint/no-unsafe-assignment */

const eslintGraphConfig = require('eslint-graph-config')
module.exports = [
  ...eslintGraphConfig,
  {
    ignores: ['typechain-types/*'],
  },
]
