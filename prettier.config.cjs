module.exports = {
  printWidth: 120,
  useTabs: false,
  bracketSpacing: true,
  singleQuote: true,
  semi: false,
  plugins: ['prettier-plugin-solidity'],
  overrides: [
    {
      files: '*.sol',
      options: {
        tabWidth: 4,
        singleQuote: false,
      },
    },
  ],
}
