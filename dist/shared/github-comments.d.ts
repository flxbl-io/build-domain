export interface Comment {
    id: number;
    body: string;
    user: {
        login: string;
    } | null;
    created_at: string;
    updated_at: string;
}
/**
 * Finds a comment in an issue/PR by a marker string.
 * The marker should be an HTML comment like <!-- marker:unique-id -->
 */
export declare function findComment(token: string, repository: string, issueNumber: number, marker: string): Promise<number | null>;
/**
 * Creates or updates a comment on an issue/PR.
 * Uses a marker to identify existing comments for updates.
 */
export declare function upsertComment(token: string, repository: string, issueNumber: number, body: string, marker: string): Promise<void>;
