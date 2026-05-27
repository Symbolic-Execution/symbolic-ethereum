import { z } from "zod";

const GITHUB_API_BASE = "https://api.github.com";

const repoInfoSchema = z.object({ default_branch: z.string() });

const githubLabelSchema = z.union([
  z.string(),
  z.object({ name: z.string().nullable() }),
]);

const githubIssueSchema = z.object({
  number: z.number(),
  title: z.string(),
  body: z.string().nullable(),
  labels: z.array(githubLabelSchema).default([]),
  comments: z.number().default(0),
  pull_request: z.unknown().optional(),
});

const githubCommentSchema = z.object({ body: z.string().nullable() });

const pullRequestSchema = z.object({
  number: z.number(),
  html_url: z.string(),
  title: z.string(),
});

const pullRequestListSchema = z.array(pullRequestSchema);

const mergeResultSchema = z.object({
  merged: z.boolean(),
  message: z.string().optional(),
});

export type GithubRepo = {
  owner: string;
  repo: string;
};

export type GithubConfig = GithubRepo & {
  token: string;
};

export type GithubIssue = {
  id: string;
  number: number;
  title: string;
  body: string;
  labels: string[];
  comments: string[];
};

export type PlannedIssue = GithubIssue & {
  branch: string;
};

export type PullRequest = z.infer<typeof pullRequestSchema>;

export class GitHubError extends Error {
  readonly status: number;

  constructor(method: string, path: string, status: number, message: string) {
    super(`GitHub ${method} ${path} failed (${status}): ${message}`);
    this.name = "GitHubError";
    this.status = status;
  }
}

export function createGithubClient(github: GithubConfig) {
  return {
    getDefaultBranch: () => getDefaultBranch(github),
    listOpenIssues: (label: string) => listOpenIssues(github, label),
    createOrUpdatePullRequest: (
      issue: PlannedIssue,
      defaultBranch: string,
      body: string,
    ) => createOrUpdatePullRequest(github, issue, defaultBranch, body),
    commentOnPullRequest: (pullNumber: number, body: string) =>
      commentOnPullRequest(github, pullNumber, body),
    squashMergePullRequest: (pr: PullRequest, issue: PlannedIssue) =>
      squashMergePullRequest(github, pr, issue),
    deleteRemoteBranch: (branch: string) => deleteRemoteBranch(github, branch),
  };
}

export type GithubClient = ReturnType<typeof createGithubClient>;

async function getDefaultBranch(github: GithubConfig) {
  const repoInfo = repoInfoSchema.parse(
    await githubRequest<unknown>(github, "GET", `/repos/${repoPath(github)}`),
  );
  return repoInfo.default_branch;
}

async function listOpenIssues(github: GithubConfig, label: string) {
  const params = new URLSearchParams({
    state: "open",
    labels: label,
    per_page: "100",
  });

  const rawIssues = z
    .array(githubIssueSchema)
    .parse(
      await githubRequest<unknown>(
        github,
        "GET",
        `/repos/${repoPath(github)}/issues?${params.toString()}`,
      ),
    )
    .filter((issue) => !issue.pull_request);

  return Promise.all(
    rawIssues.map(async (issue) => {
      const comments =
        issue.comments > 0
          ? await fetchIssueComments(github, issue.number)
          : [];

      return {
        id: String(issue.number),
        number: issue.number,
        title: issue.title,
        body: issue.body ?? "",
        labels: issue.labels
          .map((labelValue) =>
            typeof labelValue === "string" ? labelValue : labelValue.name,
          )
          .filter((name): name is string => Boolean(name)),
        comments,
      };
    }),
  );
}

async function fetchIssueComments(github: GithubConfig, issueNumber: number) {
  const comments = z
    .array(githubCommentSchema)
    .parse(
      await githubRequest<unknown>(
        github,
        "GET",
        `/repos/${repoPath(github)}/issues/${issueNumber}/comments?per_page=100`,
      ),
    );

  return comments
    .map((comment) => comment.body ?? "")
    .filter((body) => body.trim().length > 0);
}

async function createOrUpdatePullRequest(
  github: GithubConfig,
  issue: PlannedIssue,
  defaultBranch: string,
  body: string,
) {
  const existing = await findOpenPullRequest(
    github,
    issue.branch,
    defaultBranch,
  );

  if (existing) {
    return pullRequestSchema.parse(
      await githubRequest<unknown>(
        github,
        "PATCH",
        `/repos/${repoPath(github)}/pulls/${existing.number}`,
        { title: issue.title, body, base: defaultBranch },
      ),
    );
  }

  return pullRequestSchema.parse(
    await githubRequest<unknown>(github, "POST", `/repos/${repoPath(github)}/pulls`, {
      title: issue.title,
      head: issue.branch,
      base: defaultBranch,
      body,
      maintainer_can_modify: true,
    }),
  );
}

async function findOpenPullRequest(
  github: GithubConfig,
  branch: string,
  defaultBranch: string,
) {
  const params = new URLSearchParams({
    state: "open",
    head: `${github.owner}:${branch}`,
    base: defaultBranch,
  });

  const pulls = pullRequestListSchema.parse(
    await githubRequest<unknown>(
      github,
      "GET",
      `/repos/${repoPath(github)}/pulls?${params.toString()}`,
    ),
  );

  return pulls[0];
}

async function squashMergePullRequest(
  github: GithubConfig,
  pr: PullRequest,
  issue: PlannedIssue,
) {
  const result = mergeResultSchema.parse(
    await githubRequest<unknown>(
      github,
      "PUT",
      `/repos/${repoPath(github)}/pulls/${pr.number}/merge`,
      {
        merge_method: "squash",
        commit_title: `${issue.title} (#${pr.number})`,
        commit_message: `Closes #${issue.number}\n\nMerged by Sandcastle after structured review and local quality gates.`,
      },
    ),
  );

  if (!result.merged) {
    throw new Error(result.message ?? "GitHub did not merge the pull request.");
  }
}

async function deleteRemoteBranch(github: GithubConfig, branch: string) {
  try {
    await githubRequest<unknown>(
      github,
      "DELETE",
      `/repos/${repoPath(github)}/git/refs/heads/${refPath(branch)}`,
    );
  } catch (error) {
    if (error instanceof GitHubError && error.status === 404) {
      return;
    }
    throw error;
  }
}

async function commentOnPullRequest(
  github: GithubConfig,
  pullNumber: number,
  body: string,
) {
  await githubRequest<unknown>(
    github,
    "POST",
    `/repos/${repoPath(github)}/issues/${pullNumber}/comments`,
    { body },
  );
}

async function githubRequest<T>(
  github: GithubConfig,
  method: string,
  path: string,
  body?: unknown,
): Promise<T> {
  const response = await fetch(`${GITHUB_API_BASE}${path}`, {
    method,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${github.token}`,
      "Content-Type": "application/json",
      "User-Agent": "symbolic-ethereum-sandcastle",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const text = await response.text();
  if (!response.ok) {
    let message = text;
    try {
      const parsed = z.object({ message: z.string() }).parse(JSON.parse(text));
      message = parsed.message;
    } catch {
      // Keep the raw response text.
    }
    throw new GitHubError(method, path, response.status, message);
  }

  if (!text) {
    return undefined as T;
  }

  return JSON.parse(text) as T;
}

function repoPath(repo: GithubRepo) {
  return `${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.repo)}`;
}

function refPath(ref: string) {
  return ref.split("/").map(encodeURIComponent).join("/");
}
