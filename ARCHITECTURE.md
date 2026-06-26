# Architecture: Submission Privacy in AI Bounty Systems

## Section 1: Commit-Reveal (This Implementation)

### How It Works

Participants submit a cryptographic commitment — `keccak256(answer || salt || msg.sender || bountyId)` — during the submission window. The plaintext answer is never broadcast until after the submission deadline passes. In the reveal window, each participant sends their plaintext and salt; the contract recomputes the hash and accepts the answer only if it matches. After the reveal deadline, the owner calls `judgeAll`, which invokes Ritual's LLM inference precompile on the revealed answers.

### Pros

- Works on any EVM-compatible chain — no Ritual-specific primitives required during submission.
- Simple to audit: the entire flow is standard Solidity with one keccak256 hash check.
- No trusted third party: the contract enforces commitment integrity on-chain.
- Gas-efficient during submission (storing a 32-byte hash vs. full answer text).

### Cons

- Answers become public during the reveal phase — before judging completes. Any participant who reveals early leaks their answer to later revealers, who could plagiarize off-chain (though not on-chain, since commitments are already locked).
- Participants who commit but do not reveal cannot be judged. Reveal non-participation is a valid attack vector if the window is short.
- The LLM sees only revealed answers; the owner must construct the `llmInput` payload honestly. There is no on-chain enforcement that the payload faithfully represents all revealed answers.

---

## Section 2: Ritual-Native Encrypted Submissions (Advanced Design, Not Implemented)

### How It Would Work

1. **Submit phase:** Each participant encrypts their answer for the Ritual TEE (Trusted Execution Environment) executor's public key. The contract stores only the ciphertext (or an IPFS content hash + on-chain hash commitment) — no plaintext ever appears on-chain or in the mempool in a readable form.

2. **Judge phase:** The owner calls `judgeAll`. Inside the TEE, the executor decrypts all stored ciphertexts privately using the TEE's private key, runs batch LLM inference on the decrypted answers against the rubric, and produces a ranked result. At no point do unencrypted answers leave the enclave.

3. **Reveal phase (post-judging):** The TEE publishes a bundle of revealed answers off-chain (e.g., to IPFS) and stores only the content hash on-chain, providing a public audit trail after the competition closes.

### Pros

- Answers remain encrypted from submission through judging — even late submitters cannot see earlier answers.
- The LLM evaluation happens inside the TEE, so no single party (including the owner) can see all answers before judging.
- Stronger fairness guarantee: the reveal order has no strategic advantage.

### Cons

- Requires Ritual-specific primitives: DKMS precompile for key management, TEE execution environment, and the associated SDK.
- Significantly more complex to implement and audit: relies on correctness of the TEE, key management, and ciphertext storage pipeline.
- Higher gas cost for storing ciphertexts vs. 32-byte hashes.
- Off-chain IPFS dependency for the post-judging reveal bundle introduces availability risk.

---

## Section 3: Comparison

| Property | Commit-Reveal (Implemented) | Ritual TEE (Advanced) |
|---|---|---|
| Chain compatibility | Any EVM | Ritual only |
| Answers hidden during submission | Yes | Yes |
| Answers hidden during reveal | No (leaked on reveal) | Yes (never revealed until post-judging) |
| LLM sees all answers fairly | Owner-constructed payload | TEE-enforced, private |
| Complexity | Low | High |
| Auditability | High (pure Solidity) | Medium (requires TEE trust) |
| Gas cost | Low (32-byte commitment) | Higher (ciphertext storage) |
| External dependencies | None | DKMS, IPFS, TEE runtime |
