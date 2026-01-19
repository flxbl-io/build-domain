/**
 * GitHub context utilities for extracting information from GitHub Actions environment
 */
export interface GitHubContext {
    issueNumber: number | null;
    repository: string;
    owner: string;
    repo: string;
    ref: string;
    sha: string;
    eventName: string;
}
/**
 * Extracts GitHub context from environment variables.
 * Works in GitHub Actions environment.
 */
export declare function getGitHubContext(): GitHubContext;
/**
 * Parses a repository string into owner and repo parts.
 */
export declare function parseRepository(repository: string): {
    owner: string;
    repo: string;
};
