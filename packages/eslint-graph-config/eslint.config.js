// This file only exists to enable linting on index.js
const config = require('./index')
const globals = require('globals')

module.exports = [
  ...config.default,
  {
    // Additional configuration just for this package
    // since it's a commonjs module and not an ES module
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-var-requires': 'off',
    },
  },
]
