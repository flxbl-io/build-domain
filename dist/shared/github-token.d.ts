export interface AuthTokenResponse {
    token: string;
    expiresAt: string;
    type: string;
    provider: string;
    scope: string;
}
export interface ErrorResponse {
    message?: string;
    statusCode?: number;
}
/**
 * Fetches a fresh GitHub token from SFP Server.
 * Tokens are short-lived, so this should be called before operations that need GitHub access.
 */
export declare function fetchGitHubToken(serverUrl: string, serverToken: string, repository: string): Promise<string>;
