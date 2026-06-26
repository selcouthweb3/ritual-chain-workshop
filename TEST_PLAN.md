# Test Plan: AIJudge Commit-Reveal

## Setup

All tests use a local Hardhat network. Deadlines are set using `block.timestamp` offsets.
Commitment formula: `keccak256(abi.encodePacked(answer, salt, submitter, bountyId))`

---

## Test Cases

### TC-01: Valid Full Lifecycle

**Steps:**
1. Owner creates bounty with `submissionDeadline = now + 1h`, `revealDeadline = now + 2h`, reward = 1 ETH.
2. Participant A computes commitment and calls `submitCommitment`.
3. Time warp past `submissionDeadline`.
4. Participant A calls `revealAnswer` with correct answer and salt.
5. Time warp past `revealDeadline`.
6. Owner calls `judgeAll` with LLM input containing revealed answer.
7. Owner calls `finalizeWinner(bountyId, 0)`.

**Expected:** Winner receives 1 ETH; `WinnerFinalized` event emitted; `bounty.finalized == true`.

---

### TC-02: Reveal Before Submission Deadline

**Steps:**
1. Create bounty. Participant commits.
2. WITHOUT time-warping past `submissionDeadline`, call `revealAnswer`.

**Expected:** Reverts with `"submission phase still active"`.

---

### TC-03: Reveal After Reveal Deadline

**Steps:**
1. Create bounty. Participant commits.
2. Time warp past BOTH `submissionDeadline` AND `revealDeadline`.
3. Call `revealAnswer`.

**Expected:** Reverts with `"reveal phase closed"`.

---

### TC-04: Reveal With Wrong Answer

**Steps:**
1. Participant commits `keccak256("correct answer", salt, addr, bountyId)`.
2. After submission deadline, participant calls `revealAnswer("wrong answer", salt)`.

**Expected:** Reverts with `"hash mismatch"`.

---

### TC-05: Reveal With Wrong Salt

**Steps:**
1. Participant commits with `salt = bytes32("mysalt")`.
2. Reveals with `salt = bytes32("wrongsalt")` but correct answer.

**Expected:** Reverts with `"hash mismatch"`.

---

### TC-06: Double Commitment From Same Address

**Steps:**
1. Participant A calls `submitCommitment` successfully.
2. Participant A calls `submitCommitment` again (same or different commitment).

**Expected:** Reverts with `"already committed"`.

---

### TC-07: judgeAll Before Reveal Deadline

**Steps:**
1. Create bounty. Participants commit and reveal.
2. Time warp to after `submissionDeadline` but BEFORE `revealDeadline`.
3. Owner calls `judgeAll`.

**Expected:** Reverts with `"reveal phase still active"`.

---

### TC-08: finalizeWinner For Non-Revealed Submission

**Steps:**
1. Participant A commits but does NOT reveal.
2. Another participant B commits and reveals.
3. Owner judges, then calls `finalizeWinner` with participant A's index (0).

**Expected:** Reverts with `"winner did not reveal"`.

---

### TC-09: Commit With No Subsequent Reveal

**Steps:**
1. Participant A commits. Participant B commits and reveals.
2. After reveal deadline, owner calls `judgeAll`.

**Expected:** `judgeAll` succeeds (revealedCount = 1, participant B's answer is evaluated). Participant A is not eligible for the winner selection (any attempt to finalize A fails per TC-08).

---

### TC-10: judgeAll With Zero Revealed Answers

**Steps:**
1. Participant A commits but never reveals.
2. Time warp past `revealDeadline`.
3. Owner calls `judgeAll`.

**Expected:** Reverts with `"no revealed answers"`.
