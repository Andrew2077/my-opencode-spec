/**
 * Memory Database Types & Configuration
 *
 * All types, interfaces, and configuration constants for the 4-tier memory system.
 * This module has zero internal dependencies — safe to import anywhere.
 */

// ============================================================================
// Configuration
// ============================================================================

export type ConfidenceLevel = "high" | "medium" | "low";

export const MEMORY_CONFIG = {
	capture: {
		enabled: true,
		maxContentLength: 4000,
		maxAgeDays: 180,
	},
	distillation: {
		enabled: true,
		minMessages: 10,
		maxMessages: 50,
		compressionTarget: 0.2,
		topTerms: 30,
	},
	curator: {
		enabled: true,
		minDistillations: 3,
		defaultConfidence: "medium" as ConfidenceLevel,
	},
	injection: {
		enabled: true,
		tokenBudget: 2000,
		recencyDecay: 0.95,
		minScore: 0.1,
		topTerms: 30,
	},
	context: {
		enabled: true,
		maxContextTokens: 80_000,
		protectedMessages: 5,
	},
	fts: {
		tokenizer: "porter unicode61",
	},
} as const;

// ============================================================================
// Navigation Types (v3: structured navigation)
// ============================================================================

export type HallType = "facts" | "events" | "discoveries" | "preferences" | "advice";

export const VALID_HALLS: HallType[] = ["facts", "events", "discoveries", "preferences", "advice"];

// ============================================================================
// Entity Graph Types (v3: temporal knowledge graph)
// ============================================================================

export interface EntityTripleInput {
	subject: string;
	predicate: string;
	object: string;
	valid_from?: string; // ISO date or epoch
	valid_to?: string | null;
	confidence?: number; // 0.0–1.0
	source_observation_id?: number;
}

export interface EntityTripleRow {
	id: number;
	subject: string;
	predicate: string;
	object: string;
	valid_from: string;
	valid_to: string | null;
	confidence: number;
	source_observation_id: number | null;
	created_at: string;
	created_at_epoch: number;
}

export interface EntityQueryResult {
	id: number;
	subject: string;
	predicate: string;
	object: string;
	valid_from: string;
	valid_to: string | null;
	confidence: number;
	is_active: boolean;
}

// ============================================================================
// Compact Format Types (v3: AAAK-inspired compression)
// ============================================================================

export interface CompactEntry {
	code: string; // 3-letter entity code
	full: string; // Full name
	role?: string; // Role or type
}

export interface CompactResult {
	compressed: string;
	token_estimate: number;
	original_tokens: number;
	compression_ratio: number;
}

// ============================================================================
// Observation Types
// ============================================================================

export type ObservationType =
	| "decision"
	| "bugfix"
	| "feature"
	| "pattern"
	| "discovery"
	| "learning"
	| "warning";

export type ObservationSource = "manual" | "curator" | "imported";

export interface ObservationRow {
	id: number;
	type: ObservationType;
	title: string;
	subtitle: string | null;
	facts: string | null; // JSON array
	narrative: string | null;
	raw_source: string | null; // v3: verbatim source text
	concepts: string | null; // JSON array
	files_read: string | null; // JSON array
	files_modified: string | null; // JSON array
	confidence: ConfidenceLevel;
	bead_id: string | null;
	supersedes: number | null;
	superseded_by: number | null;
	valid_until: string | null;
	markdown_file: string | null;
	source: ObservationSource;
	wing: string | null; // v3: navigation wing (project/person)
	hall: HallType | null; // v3: navigation hall (facts/events/...)
	room: string | null; // v3: navigation room (topic)
	created_at: string;
	created_at_epoch: number;
	updated_at: string | null;
}

export interface ObservationInput {
	type: ObservationType;
	title: string;
	subtitle?: string;
	facts?: string[];
	narrative?: string;
	raw_source?: string; // v3: verbatim source text
	concepts?: string[];
	files_read?: string[];
	files_modified?: string[];
	confidence?: ConfidenceLevel;
	bead_id?: string;
	supersedes?: number;
	markdown_file?: string;
	source?: ObservationSource;
	wing?: string; // v3: navigation wing
	hall?: HallType; // v3: navigation hall
	room?: string; // v3: navigation room
}

export interface SearchIndexResult {
	id: number;
	type: ObservationType;
	title: string;
	snippet: string;
	created_at: string;
	relevance_score: number;
}

// ============================================================================
// Memory File Types
// ============================================================================

export interface MemoryFileRow {
	id: number;
	file_path: string;
	content: string;
	mode: "replace" | "append";
	created_at: string;
	created_at_epoch: number;
	updated_at: string | null;
	updated_at_epoch: number | null;
}

// ============================================================================
// Temporal Message Types (v2)
// ============================================================================

export interface TemporalMessageRow {
	id: number;
	session_id: string;
	message_id: string;
	role: string;
	content: string;
	token_estimate: number;
	time_created: number;
	distillation_id: number | null;
	chunk_type: string | null; // v3: exchange-pair | paragraph | sliding-window
	created_at: string;
}

export interface TemporalMessageInput {
	session_id: string;
	message_id: string;
	role: string;
	content: string;
	token_estimate: number;
	time_created: number;
	chunk_type?: string; // v3: exchange-pair | paragraph | sliding-window
}

// ============================================================================
// Distillation Types (v2)
// ============================================================================

export interface DistillationRow {
	id: number;
	session_id: string;
	content: string;
	terms: string; // JSON array of top-N TF-IDF terms
	message_count: number;
	compression_ratio: number;
	time_start: number;
	time_end: number;
	time_created: number;
	meta_distillation_id: number | null;
	created_at: string;
}

export interface DistillationInput {
	session_id: string;
	content: string;
	terms: string[];
	message_count: number;
	compression_ratio: number;
	time_start: number;
	time_end: number;
	meta_distillation_id?: number;
}

export interface DistillationSearchResult {
	id: number;
	session_id: string;
	snippet: string;
	message_count: number;
	created_at: string;
	relevance_score: number;
}

// ============================================================================
// Maintenance Types
// ============================================================================

export interface MaintenanceStats {
	archived: number;
	vacuumed: boolean;
	checkpointed: boolean;
	prunedMarkdown: number;
	purgedMessages: number;
	freedBytes: number;
	dbSizeBefore: number;
	dbSizeAfter: number;
}

export interface ArchiveOptions {
	/** Archive observations older than this many days (default: 90) */
	olderThanDays?: number;
	/** Archive superseded observations regardless of age */
	includeSuperseded?: boolean;
	/** Dry run — don't actually archive, just count */
	dryRun?: boolean;
}
