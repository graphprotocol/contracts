// @ts-check

const eslint = require('@eslint/js')
const noOnlyTests = require('eslint-plugin-no-only-tests')
const noSecrets = require('eslint-plugin-no-secrets')
const stylistic = require('@stylistic/eslint-plugin')
const tseslint = require('typescript-eslint')

// console.log(import.meta.dirname)
module.exports = tseslint.config(
  // Base eslint configuration
  eslint.configs.recommended,

  // Enable linting with type information
  // https://typescript-eslint.io/getting-started/typed-linting
  ...tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        project: ['../*/tsconfig.json', 'tsconfig.json'],
        tsconfigRootDir: __dirname,
      },
    },
  },

  // Formatting and stylistic rules
  stylistic.configs['recommended-flat'],

  // Custom rules
  {
    plugins: {
      'no-only-tests': noOnlyTests,
      'no-secrets': noSecrets,
    },
    ignores: ['dist', 'node_modules', 'coverage', 'build'],
    rules: {
      'prefer-const': 'warn',
      '@typescript-eslint/no-inferrable-types': 'warn',
      '@typescript-eslint/no-empty-function': 'warn',
      'no-only-tests/no-only-tests': 'error',
      'no-secrets/no-secrets': 'error',
      'sort-imports': [
        'warn', {
          memberSyntaxSortOrder: ['none', 'all', 'multiple', 'single'],
          ignoreCase: true,
          allowSeparatedGroups: true,
        }],
    },
  },
)
