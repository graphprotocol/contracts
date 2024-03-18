// This file only exists to enable linting on index.js
const config = require('./index')

module.exports = [
  ...config.default,
  {
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-var-requires': 'off',
    },
  },
]
