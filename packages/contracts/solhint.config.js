module.exports = {
  plugins: ['graph'],
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

    // miscellaneous
    'quotes': ['error', 'double'],

    // security
    'compiler-version': ['off'],
    'func-visibility': ['warn', { ignoreConstructors: true }],
    'not-rely-on-time': 'off',

    // graph
    // 'graph/leading-underscore': 'warn', // Contracts were originally written with a different style
  },
}
