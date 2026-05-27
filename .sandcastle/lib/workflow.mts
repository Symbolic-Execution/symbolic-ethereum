import * as sandcastle from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";
import { z } from "zod";
import {
  CommandError,
  git,
  pushBranch,
  redactSecrets,
  refreshDefaultBranch,
  runCommand,
} from "./git.mts";
import type {
  GithubClient,
  GithubConfig,
  GithubIssue,
  PlannedIssue,
} from "./github-client.mts";
import {
  buildBlockedComment,
  buildPullRequestBody,
  parseReview,
  truncateForComment,
  type QualityGateResult,
  type Review,
} from "./review-output.mts";

const hooks = {
  sandbox: { onSandboxReady: [{ command: "npm install" }] },
};

const copyToWorktree = ["node_modules"];

const planSchema = z.object({
  issues: z.array(
    z.object({ id: z.string(), title: z.string(), branch: z.string() }),
  ),
});

export async function planIssues(
  openIssues: GithubIssue[],
  token: string,
  issueLabel: string,
) {
  const plan = await sandcastle.run({
    hooks,
    sandbox: docker({ env: { GH_TOKEN: token } }),
    name: "planner",
    maxIterations: 1,
    agent: sandcastle.claudeCode("claude-opus-4-7"),
    promptFile: "./.sandcastle/plan-prompt.md",
    promptArgs: {
      ISSUES_JSON: JSON.stringify(openIssues, null, 2),
      ISSUE_LABEL: issueLabel,
    },
    output: sandcastle.Output.object({ tag: "plan", schema: planSchema }),
  });

  const issuesById = new Map(openIssues.map((issue) => [issue.id, issue]));

  return plan.output.issues.map((planned) => {
    const issue = issuesById.get(planned.id);
    if (!issue) {
      throw new Error(`Planner returned unknown issue id: ${planned.id}`);
    }

    const expectedBranch = branchForIssue(issue.id);
    if (planned.branch !== expectedBranch) {
      throw new Error(
        `Planner returned branch ${planned.branch} for issue ${planned.id}; expected ${expectedBranch}`,
      );
    }

    return { ...issue, branch: planned.branch };
  });
}

export async function runIssueWorkflow(options: {
  issue: PlannedIssue;
  github: GithubConfig;
  githubClient: GithubClient;
  defaultBranch: string;
}) {
  const { issue, github, githubClient, defaultBranch } = options;
  const sandbox = await sandcastle.createSandbox({
    branch: issue.branch,
    baseBranch: `origin/${defaultBranch}`,
    sandbox: docker({ env: { GH_TOKEN: github.token } }),
    hooks,
    copyToWorktree,
  });

  let totalCommits = 0;
  let review: Review = {
    approved: false,
    summary: "Reviewer did not run.",
    blockers: ["Reviewer did not run."],
    testNotes: "",
  };
  let gate: QualityGateResult = {
    passed: false,
    summary: "Quality gates were not run.",
    details: "Reviewer approval is required before running final quality gates.",
  };

  try {
    const implement = await sandbox.run({
      name: "implementer",
      maxIterations: 100,
      agent: sandcastle.claudeCode("claude-opus-4-7"),
      promptFile: "./.sandcastle/implement-prompt.md",
      promptArgs: {
        TASK_ID: issue.id,
        ISSUE_TITLE: issue.title,
        BRANCH: issue.branch,
      },
    });

    totalCommits += implement.commits.length;
    if (implement.commits.length === 0) {
      console.log(`#${issue.number}: no commits produced; no PR created.`);
      return;
    }

    const reviewResult = await sandbox.run({
      name: "reviewer",
      maxIterations: 1,
      agent: sandcastle.claudeCode("claude-opus-4-7"),
      promptFile: "./.sandcastle/review-prompt.md",
      promptArgs: {
        BRANCH: issue.branch,
        TARGET_BRANCH: `origin/${defaultBranch}`,
      },
    });

    totalCommits += reviewResult.commits.length;
    review = parseReview(reviewResult.stdout);

    if (review.approved) {
      gate = await runQualityGates(sandbox.worktreePath);
    }
  } finally {
    const closeResult = await sandbox.close();
    if (closeResult.preservedWorktreePath && gate.passed) {
      gate = {
        passed: false,
        summary: "Sandbox preserved a dirty worktree after the run.",
        details: `Preserved worktree: ${closeResult.preservedWorktreePath}`,
      };
    }
  }

  if (totalCommits === 0) {
    console.log(`#${issue.number}: no commits produced; no PR created.`);
    return;
  }

  await pushBranch(github, issue.branch);

  const pr = await githubClient.createOrUpdatePullRequest(
    issue,
    defaultBranch,
    buildPullRequestBody(issue, review, gate),
  );

  if (!review.approved) {
    await githubClient.commentOnPullRequest(
      pr.number,
      buildBlockedComment("Reviewer did not approve this change.", review, gate),
    );
    console.log(
      `#${issue.number}: PR left open pending review fixes: ${pr.html_url}`,
    );
    return;
  }

  if (!gate.passed) {
    await githubClient.commentOnPullRequest(
      pr.number,
      buildBlockedComment("Quality gates failed.", review, gate),
    );
    console.log(
      `#${issue.number}: PR left open because checks failed: ${pr.html_url}`,
    );
    return;
  }

  try {
    await githubClient.squashMergePullRequest(pr, issue);
    await githubClient.deleteRemoteBranch(issue.branch);
    await refreshDefaultBranch(github, defaultBranch);
    console.log(`#${issue.number}: merged ${pr.html_url}`);
  } catch (error) {
    await githubClient.commentOnPullRequest(
      pr.number,
      [
        "Sandcastle could not merge this PR automatically.",
        "",
        "Reason:",
        "```",
        truncateForComment(redactSecrets(String(error), github.token)),
        "```",
      ].join("\n"),
    );
    console.log(
      `#${issue.number}: PR left open because merge failed: ${pr.html_url}`,
    );
  }
}

async function runQualityGates(worktreePath: string): Promise<QualityGateResult> {
  const steps = [
    { name: "npm run typecheck", command: "npm", args: ["run", "typecheck"] },
    { name: "npm test", command: "npm", args: ["test"] },
  ];

  for (const step of steps) {
    try {
      await runCommand(step.command, step.args, { cwd: worktreePath });
    } catch (error) {
      if (error instanceof CommandError) {
        return {
          passed: false,
          summary: `${step.name} failed with exit code ${error.exitCode}.`,
          details: truncateForComment(
            [error.stdout, error.stderr].filter(Boolean).join("\n"),
          ),
        };
      }
      throw error;
    }
  }

  const status = await git(["status", "--porcelain"], { cwd: worktreePath });
  if (status.stdout.trim()) {
    return {
      passed: false,
      summary: "Worktree has uncommitted changes after tests.",
      details: truncateForComment(status.stdout),
    };
  }

  return { passed: true, summary: "npm run typecheck and npm test passed." };
}

function branchForIssue(id: string) {
  return `sandcastle/issue-${id}`;
}
