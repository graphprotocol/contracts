import hre from 'hardhat';
import data0 from './activeAllocations-page0.json';
import data1 from './activeAllocations-page1.json';
import { ethers } from 'ethers';
import { confirm } from '@graphprotocol/sdk';

// Set the batch size here
const BATCH_SIZE = 300;

async function main() {
    // Initialize the Graph environment
    const graph = hre.graph();
    const deployer = await graph.getDeployer();

    // Access the L1Staking contract from the graph object
    const stakingContract = graph.l1.contracts.L1Staking;

    // Extract allocation IDs from both JSON files
    const allocationIDs = [
        ...data0.data.allocations.map(allocation => allocation.id),
        ...data1.data.allocations.map(allocation => allocation.id)
    ];

    const poi = ethers.constants.HashZero; // 0x0 in bytes32 format

    // Function to split calls into batches
    function chunkArray(array, size) {
        const result = [];
        for (let i = 0; i < array.length; i += size) {
            result.push(array.slice(i, i + size));
        }
        return result;
    }

    // Split allocation IDs into batches
    const batches = chunkArray(allocationIDs, BATCH_SIZE);

    // Execute transactions for each batch
    for (let i = 0; i < batches.length; i++) {
        const batch = batches[i];

        // Encode each closeAllocation call in the current batch
        const calls = await Promise.all(batch.map(async (allocationID) => {
            return stakingContract.interface.encodeFunctionData("closeAllocation", [allocationID, poi]);
        }));

        // Fetch the current gas price
        const gasPrice = await hre.ethers.provider.getGasPrice();

        // Estimate the gas limit for the current multicall batch
        const gasLimit = await stakingContract.connect(deployer).estimateGas.multicall(calls);

        console.log(`Current gas price for batch ${i + 1}: ${ethers.utils.formatUnits(gasPrice, "gwei")} gwei`);
        console.log(`Estimated gas limit for batch ${i + 1}: ${gasLimit.toString()} units`);

        // Confirm with the user if they want to proceed with this gas price and gas limit
        const userConfirmed = await confirm(
            `Proceed with this gas price (${ethers.utils.formatUnits(gasPrice, "gwei")} gwei) and gas limit (${gasLimit.toString()} units)?`,
            false
        );
        if (!userConfirmed) {
            console.log("Transaction execution stopped by the user.");
            break;
        }

        try {
            // Send the multicall transaction for the current batch
            const tx = await stakingContract.connect(deployer).multicall(calls, { gasPrice, gasLimit });
            console.log(`Transaction sent for batch ${i + 1}: ${tx.hash}`);

            // Wait for the transaction to be mined
            const receipt = await tx.wait();

            // Check if the transaction was successful
            if (receipt.status === 1) {
                console.log(`Transaction for batch ${i + 1} mined successfully in block ${receipt.blockNumber}`);
            } else {
                console.log(`Transaction for batch ${i + 1} failed.`);
                console.log(`Failed batch first allocation ID: ${batch[0]}`);
                break;
            }
        } catch (error) {
            // Log the first allocation ID of the failed batch
            console.error(`Error executing transaction for batch ${i + 1}:`, error);
            console.log(`Failed batch first allocation ID: ${batch[0]}`);
            break;
        }
    }

    console.log("All transactions processed.");
}

// Run the script
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
