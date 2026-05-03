/**
 * Memory Database Module v3 — Barrel Export
 *
 * Re-exports all functions and types from sub-modules in ./db/.
 * This preserves backward compatibility for existing imports from "./lib/memory-db.js".
 *
 * Sub-module structure:
 *   db/types.ts        — Configuration, types, interfaces
 *   db/schema.ts       — SQL schema, migrations, DB manager
 *   db/observations.ts — Observation CRUD, search, timeline, stats
 *   db/pipeline.ts     — Temporal messages, distillations, relevance scoring
 *   db/maintenance.ts  — Memory files, FTS5, DB maintenance
 *   db/graph.ts        — Entity graph: temporal triples, queries, stats
 */

// Memory Files, FTS5, and Maintenance
export {
	archiveOldObservations,
	checkFTS5Available,
	checkpointWAL,
	getDatabaseSizes,
	getMarkdownFilesInSqlite,
	getMemoryFile,
	optimizeFTS5,
	rebuildFTS5,
	runFullMaintenance,
	upsertMemoryFile,
	vacuumDatabase,
} from "./db/maintenance.js";
// Observation Operations
export {
	getMostRecentObservation,
	getObservationById,
	getObservationStats,
	getObservationsByIds,
	getTimelineAroundObservation,
	searchObservationsFTS,
	storeObservation,
} from "./db/observations.js";
// Temporal Message & Distillation Operations
export {
	estimateTokens,
	getCaptureStats,
	getDistillationById,
	getDistillationStats,
	getRecentDistillations,
	getRelevantKnowledge,
	getUndistilledMessageCount,
	getUndistilledMessages,
	markMessagesDistilled,
	purgeOldTemporalMessages,
	searchDistillationsFTS,
	storeDistillation,
	storeTemporalMessage,
} from "./db/pipeline.js";
// Entity Graph Operations (v3)
export {
	addEntityTriple,
	findContradictions as findGraphContradictions,
	getEntityGraphStats,
	getEntityTimeline,
	getTripleById,
	invalidateTriple,
	queryEntity,
} from "./db/graph.js";
// Database Manager
export { closeMemoryDB, getMemoryDB } from "./db/schema.js";
// Types & Configuration
export * from "./db/types.js";

// New modules (v2.1: lint, compile, index, validate, operation log)
export { lintMemory, type LintResult, type LintIssue, type LintIssueType } from "./lint.js";
export { generateMemoryIndex, type IndexResult, type IndexEntry } from "./index-generator.js";
export { appendOperationLog, getRecentLogEntries, getLogContent, type LogEntry, type OperationType } from "./operation-log.js";
export { compileObservations, type CompileResult, type CompiledArticle, type ConceptCluster } from "./compile.js";
export { validateObservation, type ValidationResult, type ValidationVerdict, type ValidationIssue } from "./validate.js";
