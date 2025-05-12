/** @type {import('eslint').Linter.Config} */
module.exports = [
  {
    ignores: ['build/**', 'node_modules/**'],
  },
  {
    rules: {
      'no-console': 'warn',
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },
]
