import { execFile } from "node:child_process";
import type { GithubConfig, GithubRepo } from "./github-client.mts";

const COMMAND_MAX_BUFFER = 20 * 1024 * 1024;

export class CommandError extends Error {
  readonly stdout: string;
  readonly stderr: string;
  readonly exitCode: number;

  constructor(
    command: string,
    args: string[],
    exitCode: number,
    stdout: string,
    stderr: string,
  ) {
    super(`Command failed (${exitCode}): ${[command, ...args].join(" ")}`);
    this.name = "CommandError";
    this.exitCode = exitCode;
    this.stdout = stdout;
    this.stderr = stderr;
  }
}

export async function refreshDefaultBranch(
  github: GithubConfig,
  defaultBranch: string,
) {
  const currentBranch = (await git(["branch", "--show-current"])).stdout.trim();
  if (currentBranch !== defaultBranch) {
    throw new Error(
      `Run Sandcastle from ${defaultBranch}; current branch is ${currentBranch}.`,
    );
  }

  await git(
    [
      "fetch",
      "--prune",
      httpsRemoteUrl(github),
      `+refs/heads/${defaultBranch}:refs/remotes/origin/${defaultBranch}`,
    ],
    { env: authenticatedGitEnv(github.token) },
  );
  await git(["merge", "--ff-only", `origin/${defaultBranch}`]);
}

export async function pushBranch(github: GithubConfig, branch: string) {
  await fetchRemoteBranchIfExists(github, branch);

  await git(
    [
      "push",
      "--force-with-lease",
      httpsRemoteUrl(github),
      `${branch}:refs/heads/${branch}`,
    ],
    { env: authenticatedGitEnv(github.token) },
  );
}

export async function git(
  args: string[],
  options: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
) {
  return runCommand("git", args, options);
}

export async function runCommand(
  command: string,
  args: string[],
  options: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
) {
  return new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
    execFile(
      command,
      args,
      {
        cwd: options.cwd,
        env: options.env ?? process.env,
        maxBuffer: COMMAND_MAX_BUFFER,
      },
      (error, stdout, stderr) => {
        const envToken = bearerTokenFromHeader(options.env?.GIT_CONFIG_VALUE_0);
        const cleanStdout = redactSecrets(String(stdout), envToken);
        const cleanStderr = redactSecrets(String(stderr), envToken);

        if (error) {
          const exitCode = typeof error.code === "number" ? error.code : 1;
          reject(
            new CommandError(
              command,
              args,
              exitCode,
              cleanStdout,
              cleanStderr,
            ),
          );
          return;
        }

        resolve({ stdout: cleanStdout, stderr: cleanStderr });
      },
    );
  });
}

function authenticatedGitEnv(token: string): NodeJS.ProcessEnv {
  return {
    ...process.env,
    GIT_CONFIG_COUNT: "1",
    GIT_CONFIG_KEY_0: "http.https://github.com/.extraheader",
    GIT_CONFIG_VALUE_0: `AUTHORIZATION: bearer ${token}`,
  };
}

function httpsRemoteUrl(repo: GithubRepo) {
  return `https://github.com/${repo.owner}/${repo.repo}.git`;
}

async function fetchRemoteBranchIfExists(github: GithubConfig, branch: string) {
  try {
    await git(
      [
        "fetch",
        httpsRemoteUrl(github),
        `+refs/heads/${branch}:refs/remotes/origin/${branch}`,
      ],
      { env: authenticatedGitEnv(github.token) },
    );
  } catch (error) {
    if (
      error instanceof CommandError &&
      error.stderr.includes("couldn't find remote ref")
    ) {
      return;
    }
    throw error;
  }
}

export function redactSecrets(value: string, token?: string) {
  let result = value;
  const secrets = [token, process.env.GH_TOKEN, process.env.GITHUB_TOKEN].filter(
    (secret): secret is string => Boolean(secret),
  );

  for (const secret of secrets) {
    result = result.split(secret).join("[redacted]");
  }

  return result;
}

function bearerTokenFromHeader(value: string | undefined) {
  const match = value?.match(/^AUTHORIZATION:\s*bearer\s+(.+)$/i);
  return match?.[1];
}
