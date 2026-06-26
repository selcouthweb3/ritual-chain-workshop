import hre from "hardhat";
import { parseEther } from "viem";
import { writeFileSync } from "fs";
import { join } from "path";

const RITUAL_WALLET = "0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948" as const;

const RITUAL_WALLET_ABI = [
  {
    name: "depositFor",
    type: "function",
    stateMutability: "payable",
    inputs: [
      { name: "user", type: "address" },
      { name: "lockDuration", type: "uint256" },
    ],
    outputs: [],
  },
] as const;

async function main() {
  const publicClient = await hre.viem.getPublicClient();
  const [deployer] = await hre.viem.getWalletClients();

  console.log("Deployer:", deployer.account.address);

  const artifact = await hre.artifacts.readArtifact("AIJudge");

  const deployHash = await deployer.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode as `0x${string}`,
    args: [],
  });

  console.log("Deploy tx:", deployHash);

  const receipt = await publicClient.waitForTransactionReceipt({ hash: deployHash });
  const contractAddress = receipt.contractAddress!;

  console.log("AIJudge deployed to:", contractAddress);

  // Deposit 0.01 RITUAL into RitualWallet for the contract
  console.log("Depositing 0.01 RITUAL into RitualWallet for contract...");
  const depositHash = await deployer.writeContract({
    address: RITUAL_WALLET,
    abi: RITUAL_WALLET_ABI,
    functionName: "depositFor",
    args: [contractAddress, 0n],
    value: parseEther("0.01"),
  });

  await publicClient.waitForTransactionReceipt({ hash: depositHash });
  console.log("RitualWallet deposit tx:", depositHash);

  const infoPath = join(process.cwd(), "..", "deployment-info.txt");
  writeFileSync(
    infoPath,
    `CONTRACT_ADDRESS=${contractAddress}\nDEPLOYMENT_TX=${deployHash}\n`
  );
  console.log("Deployment info saved to:", infoPath);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
