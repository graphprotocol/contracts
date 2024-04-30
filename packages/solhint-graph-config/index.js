module.exports = {
  extends: 'solhint:recommended',
  rules: {
    // best practices
    'no-empty-blocks': 'off',
    'constructor-syntax': 'warn',

    // style rules
    // 'private-vars-leading-underscore': ['warn', { strict: false }],
    'const-name-snakecase': 'warn',
    'immutable-vars-naming': 'warn',
    'named-parameters-mapping': 'warn',
    'imports-on-top': 'warn',
    'ordering': 'warn',
    'visibility-modifier-order': 'warn',
    
    // miscellaneous
    'quotes': ['error', 'double'],

    // security
    'compiler-version': ['off'],
    'func-visibility': ['warn', { ignoreConstructors: true }],
    'not-rely-on-time': 'off',
  },
}
