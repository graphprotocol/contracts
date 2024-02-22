import eslint from '@eslint/js'
import globals from 'globals'
import noOnlyTests from 'eslint-plugin-no-only-tests'
import noSecrets from 'eslint-plugin-no-secrets'
import stylistic from '@stylistic/eslint-plugin'
import tseslint from 'typescript-eslint'

export default tseslint.config(
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
      globals: {
        ...globals.node,
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
    ignores: ['dist/*', 'node_modules/*', 'build/*'],
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
