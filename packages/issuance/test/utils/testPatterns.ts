/* eslint-disable @typescript-eslint/no-explicit-any */
/**
 * Shared test patterns and utilities to reduce duplication across test files
 */

const { expect } = require('chai')

// Test constants - centralized to avoid magic numbers
export const TestConstants = {
  // Interface IDs
  IERC165_INTERFACE_ID: '0x01ffc9a7',
} as const

/**
 * Shared test pattern for ERC-165 interface compliance
 */
export function shouldSupportERC165Interface<T>(contractGetter: () => T, interfaceId: string, interfaceName: string) {
  return function () {
    it(`should support ERC-165 interface`, async function () {
      const contract = contractGetter()
      expect(await (contract as any).supportsInterface(TestConstants.IERC165_INTERFACE_ID)).to.be.true
    })

    it(`should support ${interfaceName} interface`, async function () {
      const contract = contractGetter()
      expect(await (contract as any).supportsInterface(interfaceId)).to.be.true
    })

    it('should not support random interface', async function () {
      const contract = contractGetter()
      const randomInterfaceId = '0x12345678'
      expect(await (contract as any).supportsInterface(randomInterfaceId)).to.be.false
    })
  }
}
