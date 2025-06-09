/**
 * Mock implementation of the L2ArbitrumMessenger contract
 * This is used to override the sendTxToL1 function in the L2GraphTokenGateway contract
 */
export class L2ArbitrumMessengerMock {
  private static _calls: Array<{
    l1CallValue: number
    from: string
    to: string
    data: string
  }> = []

  /**
   * Mock implementation of sendTxToL1 function
   * @param l1CallValue The call value to send to L1
   * @param from The sender address
   * @param to The destination address on L1
   * @param data The calldata to send to L1
   * @returns A transaction ID (always returns 1)
   */
  public static sendTxToL1(l1CallValue: number, from: string, to: string, data: string): number {
    this._calls.push({ l1CallValue, from, to, data })
    return 1 // Always return 1 as the transaction ID
  }

  /**
   * Check if sendTxToL1 was called with specific arguments
   * @param to The expected destination address
   * @param data The expected calldata
   * @returns true if the function was called with the specified arguments
   */
  public static calledWith(to: string, data: string): boolean {
    return this._calls.some((call) => call.to === to && call.data === data)
  }

  /**
   * Reset all recorded calls
   */
  public static reset(): void {
    this._calls = []
  }

  /**
   * Get the number of times sendTxToL1 was called
   */
  public static get callCount(): number {
    return this._calls.length
  }
}
