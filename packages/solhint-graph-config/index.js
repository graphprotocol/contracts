module.exports = {
  extends: 'solhint:recommended',
  rules: {
    'func-visibility': ['warn', { ignoreConstructors: true }],
    'compiler-version': ['off'],
    'constructor-syntax': 'warn',
    'quotes': ['error', 'double'],
    'reason-string': ['off'],
    'not-rely-on-time': 'off',
    'no-empty-blocks': 'off',
  },
}
