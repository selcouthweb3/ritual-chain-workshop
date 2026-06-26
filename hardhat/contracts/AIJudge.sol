// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;

    function depositFor(address user, uint256 lockDuration) external payable;

    function withdraw(uint256 amount) external;

    function balanceOf(address) external view returns (uint256);

    function lockUntil(address) external view returns (uint256);
}

contract AIJudge is PrecompileConsumer {
    uint256 public constant MAX_SUBMISSIONS = 10;
    uint256 public constant MAX_ANSWER_LENGTH = 2_000;

    uint256 public nextBountyId = 1;

    IRitualWallet wallet =
        IRitualWallet(0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948);

    struct Submission {
        address submitter;
        string answer;
        bytes32 commitment;
        bool revealed;
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool judged;
        bool finalized;
        bytes aiReview;
        uint256 winnerIndex;
        Submission[] submissions;
    }

    struct ConvoHistory {
        string storageType;
        string path;
        string secretsName;
    }

    mapping(uint256 => Bounty) public bounties;

    // Prevents duplicate commitments per user per bounty
    mapping(uint256 => mapping(address => bool)) public hasCommitted;

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string title,
        uint256 reward,
        uint256 deadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter,
        bytes32 commitment
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter,
        string answer
    );

    event AllAnswersJudged(uint256 indexed bountyId, bytes aiReview);

    event WinnerFinalized(
        uint256 indexed bountyId,
        uint256 indexed winnerIndex,
        address indexed winner,
        uint256 reward
    );

    modifier onlyOwner(uint256 bountyId) {
        require(msg.sender == bounties[bountyId].owner, "not bounty owner");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].owner != address(0), "bounty not found");
        _;
    }

    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 submissionDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0, "reward required");
        require(
            revealDeadline > submissionDeadline,
            "revealDeadline must be after submissionDeadline"
        );

        bountyId = nextBountyId++;

        Bounty storage bounty = bounties[bountyId];

        bounty.owner = msg.sender;
        bounty.title = title;
        bounty.rubric = rubric;
        bounty.reward = msg.value;
        bounty.submissionDeadline = submissionDeadline;
        bounty.revealDeadline = revealDeadline;
        bounty.winnerIndex = type(uint256).max;

        emit BountyCreated(bountyId, msg.sender, title, msg.value, revealDeadline);
    }

    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(block.timestamp < bounty.submissionDeadline, "submission phase closed");
        require(!hasCommitted[bountyId][msg.sender], "already committed");
        require(bounty.submissions.length < MAX_SUBMISSIONS, "too many submissions");

        bounty.submissions.push(
            Submission({
                submitter: msg.sender,
                commitment: commitment,
                revealed: false,
                answer: ""
            })
        );
        hasCommitted[bountyId][msg.sender] = true;

        emit CommitmentSubmitted(
            bountyId,
            bounty.submissions.length - 1,
            msg.sender,
            commitment
        );
    }

    // commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(block.timestamp >= bounty.submissionDeadline, "submission phase still active");
        require(block.timestamp < bounty.revealDeadline, "reveal phase closed");
        require(bytes(answer).length <= MAX_ANSWER_LENGTH, "answer too long");

        uint256 submissionIndex = type(uint256).max;
        for (uint256 i = 0; i < bounty.submissions.length; i++) {
            if (bounty.submissions[i].submitter == msg.sender) {
                submissionIndex = i;
                break;
            }
        }
        require(submissionIndex != type(uint256).max, "no commitment found");

        Submission storage submission = bounty.submissions[submissionIndex];
        require(!submission.revealed, "already revealed");

        bytes32 expectedHash = keccak256(
            abi.encodePacked(answer, salt, msg.sender, bountyId)
        );
        require(expectedHash == submission.commitment, "hash mismatch");

        submission.answer = answer;
        submission.revealed = true;

        emit AnswerRevealed(bountyId, submissionIndex, msg.sender, answer);
    }

    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(!bounty.judged, "already judged");
        require(!bounty.finalized, "already finalized");
        require(block.timestamp >= bounty.revealDeadline, "reveal phase still active");

        uint256 revealedCount = 0;
        for (uint256 i = 0; i < bounty.submissions.length; i++) {
            if (bounty.submissions[i].revealed) {
                revealedCount++;
            }
        }
        require(revealedCount > 0, "no revealed answers");

        bytes memory output = _executePrecompile(
            LLM_INFERENCE_PRECOMPILE,
            llmInput
        );

        (
            bool hasError,
            bytes memory completionData,
            ,
            string memory errorMessage,

        ) = abi.decode(output, (bool, bytes, bytes, string, ConvoHistory));

        require(!hasError, errorMessage);

        bounty.judged = true;
        bounty.aiReview = completionData;

        emit AllAnswersJudged(bountyId, completionData);
    }

    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(bounty.judged, "not judged yet");
        require(!bounty.finalized, "already finalized");
        require(bounty.submissions[winnerIndex].revealed, "winner did not reveal");

        bounty.finalized = true;
        bounty.winnerIndex = winnerIndex;

        address winner = bounty.submissions[winnerIndex].submitter;
        uint256 reward = bounty.reward;
        bounty.reward = 0;

        (bool ok, ) = payable(winner).call{value: reward}("");
        require(ok, "payment failed");

        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    function getBounty(
        uint256 bountyId
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address owner,
            string memory title,
            string memory rubric,
            uint256 reward,
            uint256 submissionDeadline,
            uint256 revealDeadline,
            bool judged,
            bool finalized,
            uint256 submissionCount,
            uint256 winnerIndex,
            bytes memory aiReview
        )
    {
        Bounty storage bounty = bounties[bountyId];

        return (
            bounty.owner,
            bounty.title,
            bounty.rubric,
            bounty.reward,
            bounty.submissionDeadline,
            bounty.revealDeadline,
            bounty.judged,
            bounty.finalized,
            bounty.submissions.length,
            bounty.winnerIndex,
            bounty.aiReview
        );
    }

    function getSubmission(
        uint256 bountyId,
        uint256 index
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address submitter,
            string memory answer,
            bytes32 commitment,
            bool revealed
        )
    {
        Bounty storage bounty = bounties[bountyId];

        require(index < bounty.submissions.length, "invalid index");

        Submission storage submission = bounty.submissions[index];

        return (
            submission.submitter,
            submission.answer,
            submission.commitment,
            submission.revealed
        );
    }
}
