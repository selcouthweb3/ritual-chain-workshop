# Ritual AI Bounty Judge — Commit-Reveal Submission

A smart contract bounty system built on the Ritual testnet that uses a commit-reveal scheme to keep answers hidden until the reveal phase, followed by on-chain AI judging via Ritual's LLM inference precompile.

## Overview

Participants commit a hash of their answer during the submission window, keeping the content hidden from other submitters. After the submission deadline passes, they reveal their plaintext answer. Once the reveal window closes, the bounty owner triggers on-chain LLM inference (via Ritual's precompile) to score all revealed answers against the rubric. The owner then selects and pays the winner — the financial trigger is always human-authorized.

## Bounty Lifecycle (5 phases)

| Phase | Actor | Action |
|---|---|---|
| 1. **Create** | Owner | Call `createBounty` with title, rubric, `submissionDeadline`, `revealDeadline`, and ETH reward |
| 2. **Commit** | Participants | Call `submitCommitment` with `keccak256(answer ++ salt ++ msg.sender ++ bountyId)` |
| 3. **Reveal** | Participants | Call `revealAnswer` with plaintext answer and salt after submission deadline |
| 4. **Judge** | Owner | Call `judgeAll` with LLM input payload after reveal deadline — Ritual runs on-chain inference |
| 5. **Finalize** | Owner | Call `finalizeWinner` to select winner index and pay reward |

## Commitment Formula

```
commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
```

**Why `msg.sender` is included:** Prevents commitment stealing — an attacker cannot copy someone else's commitment to a different address, because their address won't match when they try to reveal.

**Why `bountyId` is included:** Prevents cross-bounty replay — the same answer+salt pair produces a different hash for each bounty, so a commitment from one bounty cannot be reused in another.

## Required Function Signatures

```solidity
// Create bounty with two deadlines
function createBounty(
    string calldata title,
    string calldata rubric,
    uint256 submissionDeadline,
    uint256 revealDeadline
) external payable returns (uint256 bountyId);

// Submit commitment hash (before submissionDeadline)
function submitCommitment(uint256 bountyId, bytes32 commitment) external;

// Reveal plaintext answer (between submissionDeadline and revealDeadline)
function revealAnswer(uint256 bountyId, string calldata answer, bytes32 salt) external;

// Run LLM judging (after revealDeadline, owner only)
function judgeAll(uint256 bountyId, bytes calldata llmInput) external;

// Pay winner (after judging, owner only)
function finalizeWinner(uint256 bountyId, uint256 winnerIndex) external;
```

## Deployment

Network: Ritual testnet (Chain ID: 1979)
RPC: `https://rpc.ritualfoundation.org`

| | |
|---|---|
| Contract address | `0x13449585c4f80c6fd91d8518c93c28d6d7a0fa7c` |
| Deployment tx | `0x887a28cd70dea61056229705271164e3a070503e74fea84730351bae94773f9c` |

## Repository Structure

```
hardhat/contracts/AIJudge.sol     Main contract
hardhat/scripts/deployAIJudge.ts  Deployment script
hardhat/hardhat.config.ts         Hardhat 3 config
web/                              Next.js frontend
deployment-info.txt               Contract address + tx hash
```
