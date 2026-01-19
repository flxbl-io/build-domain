export interface ChangelogOptions {
    environment: string;
    domain: string;
    releaseCandidate: string;
    repository: string;
    serverUrl: string;
    serverToken: string;
    outputDir?: string;
}
export interface ChangelogResult {
    success: boolean;
    markdownPath: string | null;
    jsonPath: string | null;
    content: string | null;
    error?: string;
}
export type ReleaseStatus = 'success' | 'partial' | 'failed' | 'dry-run';
/**
 * Generates a changelog using the sfp changelog from-env command.
 */
export declare function generateChangelog(options: ChangelogOptions): Promise<ChangelogResult>;
/**
 * Formats a changelog as a GitHub comment with status header.
 * @param content - The markdown changelog content
 * @param status - The release status
 * @param releaseCandidates - Release candidates in format "domain:name" or "domain1:name1,domain2:name2"
 * @param environment - Target environment name
 */
export declare function formatChangelogComment(content: string, status: ReleaseStatus, releaseCandidates: string, environment: string): string;
