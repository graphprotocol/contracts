import eslint from '@eslint/js'
import globals from 'globals'
import noOnlyTests from 'eslint-plugin-no-only-tests'
import noSecrets from 'eslint-plugin-no-secrets'
import stylistic from '@stylistic/eslint-plugin'
import tseslint from 'typescript-eslint'

export default [
  // Base eslint configuration
  eslint.configs.recommended,

  // Enable linting with type information
  // https://typescript-eslint.io/getting-started/typed-linting
  ...tseslint.configs.recommendedTypeChecked,

  // Formatting and stylistic rules
  stylistic.configs['recommended-flat'],

  // Custom config
  {
    languageOptions: {
      parserOptions: {
        project: ['../*/tsconfig.json', 'tsconfig.json'],
        tsconfigRootDir: __dirname,
      },
      globals: {
        ...globals.node,
      },
    },
    plugins: {
      'no-only-tests': noOnlyTests,
      'no-secrets': noSecrets,
    },
    rules: {
      'prefer-const': 'warn',
      '@typescript-eslint/no-inferrable-types': 'warn',
      '@typescript-eslint/no-empty-function': 'warn',
      'no-only-tests/no-only-tests': 'error',
      'no-secrets/no-secrets': ['error', { tolerance: 4.1 }],
      'sort-imports': [
        'warn', {
          memberSyntaxSortOrder: ['none', 'all', 'multiple', 'single'],
          ignoreCase: true,
          allowSeparatedGroups: true,
        }],
      '@stylistic/brace-style': ['error', '1tbs'],
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          args: 'all',
          argsIgnorePattern: '^_',
          caughtErrors: 'all',
          caughtErrorsIgnorePattern: '^_',
          destructuredArrayIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          ignoreRestSiblings: true,
        },
      ],
    },
  },
  {
    ignores: ['**/dist/*', '**/node_modules/*', '**/build/*', '**/cache/*', '**/.graphclient/*'],
  },
]
