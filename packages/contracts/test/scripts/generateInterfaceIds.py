#!/usr/bin/env python3

"""
Generate interface ID constants by deploying and calling InterfaceIdExtractor contract
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def log(*args):
    """Print log message if not in silent mode"""
    if "--silent" not in sys.argv:
        print(*args)


def run_hardhat_task():
    """Run hardhat script to extract interface IDs"""
    hardhat_script = """
const hre = require('hardhat')

async function main() {
  const InterfaceIdExtractor = await hre.ethers.getContractFactory('InterfaceIdExtractor')
  const extractor = await InterfaceIdExtractor.deploy()
  await extractor.deployed()
  
  const results = {
    IRewardsManager: await extractor.getIRewardsManagerId(),
    IIssuanceTarget: await extractor.getIIssuanceTargetId(),
    IERC165: await extractor.getIERC165Id(),
  }
  
  console.log(JSON.stringify(results))
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
"""

    script_dir = Path(__file__).parent
    project_dir = script_dir.parent.parent

    # Write temporary script
    with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False) as temp_file:
        temp_file.write(hardhat_script)
        temp_script = temp_file.name

    try:
        # Run the script with hardhat
        result = subprocess.run(
            ['npx', 'hardhat', 'run', temp_script, '--network', 'hardhat'],
            cwd=project_dir,
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode != 0:
            raise RuntimeError(f"Hardhat script failed with code {result.returncode}: {result.stderr}")

        # Extract JSON from output
        for line in result.stdout.split('\n'):
            line = line.strip()
            if line:
                try:
                    data = json.loads(line)
                    if isinstance(data, dict):
                        return data
                except json.JSONDecodeError:
                    # Not JSON, continue - this is expected for non-JSON output lines
                    continue

        raise RuntimeError("Could not parse interface IDs from output")

    finally:
        # Clean up temp script
        try:
            os.unlink(temp_script)
        except OSError:
            # Ignore cleanup errors - temp file may not exist
            pass


def extract_interface_ids():
    """Extract interface IDs using the InterfaceIdExtractor contract"""
    script_dir = Path(__file__).parent
    extractor_path = script_dir.parent.parent / "artifacts" / "contracts" / "tests" / "InterfaceIdExtractor.sol" / "InterfaceIdExtractor.json"

    if not extractor_path.exists():
        print("❌ InterfaceIdExtractor artifact not found")
        print("Run: pnpm compile to build the extractor contract")
        raise RuntimeError("InterfaceIdExtractor not compiled")

    log("Deploying InterfaceIdExtractor contract to extract interface IDs...")

    try:
        results = run_hardhat_task()

        # Convert from ethers BigNumber format to hex strings
        processed = {}
        for name, value in results.items():
            if isinstance(value, str):
                processed[name] = value
            else:
                # Convert number to hex string
                processed[name] = f"0x{int(value):08x}"
            log(f"✅ Extracted {name}: {processed[name]}")

        return processed

    except Exception as error:
        print(f"Error extracting interface IDs: {error}")
        raise


def main():
    """Main function to generate interface IDs TypeScript file"""
    log("Extracting interface IDs from Solidity compilation...")

    results = extract_interface_ids()

    # Generate TypeScript content
    content = f"""// Auto-generated interface IDs from Solidity compilation
export const INTERFACE_IDS = {{
{chr(10).join(f"  {name}: '{id_value}'," for name, id_value in results.items())}
}} as const

// Individual exports for convenience
{chr(10).join(f"export const {name} = '{id_value}'" for name, id_value in results.items())}
"""

    # Write to output file
    script_dir = Path(__file__).parent
    output_file = script_dir.parent / "helpers" / "interfaceIds.ts"
    
    # Create helpers directory if it doesn't exist
    output_file.parent.mkdir(exist_ok=True)
    
    with open(output_file, 'w') as f:
        f.write(content)
    
    log(f"✅ Generated {output_file}")


if __name__ == "__main__":
    main()
