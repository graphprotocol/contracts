module.exports = {
  plugins: [ 'graph' ],
  extends: 'solhint:recommended',
  rules: {
    // best practices
    'no-empty-blocks': 'off',
    'constructor-syntax': 'warn',

    // style rules
    'private-vars-leading-underscore': 'off', // see graph/leading-underscore
    'const-name-snakecase': 'warn',
    'named-parameters-mapping': 'warn',
    'imports-on-top': 'warn',
    'ordering': 'warn',
    'visibility-modifier-order': 'warn',
    'func-name-mixedcase': 'off', // see graph/func-name-mixedcase
    'var-name-mixedcase': 'off', // see graph/var-name-mixedcase
    
    // miscellaneous
    'quotes': ['error', 'double'],

    // security
    'compiler-version': ['off'],
    'func-visibility': ['warn', { ignoreConstructors: true }],
    'not-rely-on-time': 'off',

    // graph
    'graph/leading-underscore': 'warn',
    'graph/func-name-mixedcase': 'warn',
    'graph/var-name-mixedcase': 'warn',
    'gas-custom-errors': 'off'
  },
}
