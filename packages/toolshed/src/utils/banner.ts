/**
 * Creates and prints a box-style banner with centered text to the console
 * @param title The main title text to display
 * @param prefix Optional prefix text that appears before the title (default: '')
 * @param minWidth Minimum width of the banner (default: 47)
 */
export function printBanner(title: string, prefix = '', minWidth = 47): void {
  // Format title with capitalized words if it contains hyphens
  const formattedTitle = title.includes('-')
    ? title
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
    : title

  const fullText = prefix + formattedTitle

  // Calculate minimum banner width needed for the text
  const contentWidth = fullText.length
  const bannerWidth = Math.max(minWidth, contentWidth + 10) // Add padding

  // Create the centered text line
  const paddingLeft = Math.floor((bannerWidth - contentWidth) / 2)
  const paddingRight = bannerWidth - contentWidth - paddingLeft
  const centeredLine = '|' + ' '.repeat(paddingLeft) + fullText + ' '.repeat(paddingRight) + '|'

  // Create empty line with correct width
  const emptyLine = '|' + ' '.repeat(bannerWidth) + '|'

  // Create border with correct width
  const border = '+' + '-'.repeat(bannerWidth) + '+'

  console.log(`
${border}
${emptyLine}
${centeredLine}
${emptyLine}
${border}
`)
}

export function printHorizonBanner() {
  console.log(`
  ██╗  ██╗ ██████╗ ██████╗ ██╗███████╗ ██████╗ ███╗   ██╗
  ██║  ██║██╔═══██╗██╔══██╗██║╚══███╔╝██╔═══██╗████╗  ██║
  ███████║██║   ██║██████╔╝██║  ███╔╝ ██║   ██║██╔██╗ ██║
  ██╔══██║██║   ██║██╔══██╗██║ ███╔╝  ██║   ██║██║╚██╗██║
  ██║  ██║╚██████╔╝██║  ██║██║███████╗╚██████╔╝██║ ╚████║
  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
                                                          
  ██╗   ██╗██████╗  ██████╗ ██████╗  █████╗ ██████╗ ███████╗
  ██║   ██║██╔══██╗██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██╔════╝
  ██║   ██║██████╔╝██║  ███╗██████╔╝███████║██║  ██║█████╗  
  ██║   ██║██╔═══╝ ██║   ██║██╔══██╗██╔══██║██║  ██║██╔══╝  
  ╚██████╔╝██║     ╚██████╔╝██║  ██║██║  ██║██████╔╝███████╗
   ╚═════╝ ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝
  `)
}
