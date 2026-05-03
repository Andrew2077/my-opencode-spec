/**
 * Memory Plugin — Admin Tools
 *
 * memory-admin (12 operations).
 *
 * Uses factory pattern: createAdminTools(deps) returns tool definitions.
 */

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { tool } from "@opencode-ai/plugin/tool";
import { curateFromDistillations } from "./curator.js";
import { compileObservations } from "./compile.js";
import { distillSession } from "./distill.js";
import { generateMemoryIndex } from "./index-generator.js";
import { lintMemory } from "./lint.js";
import { getLogContent } from "./operation-log.js";
import {
	archiveOldObservations,
	type ConfidenceLevel,
	checkFTS5Available,
	checkpointWAL,
	findGraphContradictions,
	getCaptureStats,
	getDatabaseSizes,
	getDistillationStats,
	getEntityGraphStats,
	getMarkdownFilesInSqlite,
	getMemoryDB,
	getObservationStats,
	type ObservationType,
	rebuildFTS5,
	runFullMaintenance,
	storeObservation,
	vacuumDatabase,
} from "./memory-db.js";

interface AdminToolDeps {
	directory: string;
}

export function createAdminTools(deps: AdminToolDeps) {
	const { directory } = deps;

	return {
		"memory-admin": tool({
			description: `Memory system administration: maintenance and migration.\n\nOperations:\n- "status": Storage stats and recommendations\n- "full": Full maintenance cycle (archive + checkpoint + vacuum)\n- "archive": Archive old observations (>90 days default)\n- "checkpoint": Checkpoint WAL file\n- "vacuum": Vacuum database\n- "migrate": Import .opencode/memory/observations/*.md into SQLite\n- "capture-stats": Temporal message capture statistics\n- "distill-now": Force distillation for current session\n- "curate-now": Force curator run\n- "lint": Run lint checks (duplicates, contradictions, stale, orphans)\n- "index": Generate memory index catalog\n- "compile": Compile observations into structured articles\n- "log": View operation log\n\nExample:\nmemory-admin({ operation: "status" })\nmemory-admin({ operation: "migrate", dry_run: true })\nmemory-admin({ operation: "lint" })\nmemory-admin({ operation: "compile" })`,
			args: {
				operation: tool.schema
					.string()
					.optional()
					.describe("Operation (default: status)"),
				older_than_days: tool.schema
					.number()
					.optional()
					.describe("Archive threshold (default: 90)"),
				dry_run: tool.schema
					.boolean()
					.optional()
					.describe("Preview without executing"),
				force: tool.schema.boolean().optional().describe("Force re-migration"),
			},
			execute: async (args, ctx) => {
				try {
					const op = args.operation ?? "status";
					const dryRun = args.dry_run ?? false;
					const olderThanDays = args.older_than_days ?? 90;

					switch (op) {
						case "status": {
							const sizes = getDatabaseSizes();
							const stats = getObservationStats();
							const archivable = archiveOldObservations({
								olderThanDays,
								dryRun: true,
							});
							const captureStats = getCaptureStats();
							const distillStats = getDistillationStats();
							const graphStats = getEntityGraphStats();
							return [
								"## Memory System Status\n",
								`**Database**: ${(sizes.total / 1024).toFixed(1)} KB`,
								`**FTS5**: ${checkFTS5Available() ? "Available (porter stemming)" : "Unavailable"}`,
								`**Schema**: v3 (4-tier + entity graph)\n`,
								"### Observations",
								...Object.entries(stats).map(([k, v]) => `  ${k}: ${v}`),
								`  Archivable (>${olderThanDays}d): ${archivable}\n`,
								"### Capture Pipeline",
								`  Messages: ${captureStats.total} (undistilled: ${captureStats.undistilled})`,
								`  Sessions: ${captureStats.sessions}\n`,
								"### Distillations",
								`  Total: ${distillStats.total} (${distillStats.sessions} sessions)`,
								`  Avg compression: ${(distillStats.avgCompression * 100).toFixed(1)}%\n`,
								"### Entity Graph",
								`  Triples: ${graphStats.total_triples} (active: ${graphStats.active_triples})`,
								`  Entities: ${graphStats.unique_entities}`,
								`  Predicates: ${graphStats.unique_predicates}`,
							].join("\n");
						}
						case "full": {
							if (dryRun)
								return `Dry run: would archive, purge, optimize, checkpoint, vacuum.`;
							const r = runFullMaintenance({
								olderThanDays,
								includeSuperseded: true,
							});
							return `Done: archived ${r.archived}, purged ${r.purgedMessages} msgs, freed ${(r.freedBytes / 1024).toFixed(1)} KB.`;
						}
						case "archive": {
							const c = archiveOldObservations({
								olderThanDays,
								includeSuperseded: true,
								dryRun,
							});
							return dryRun
								? `Would archive ${c} observations.`
								: `Archived ${c} observations.`;
						}
						case "checkpoint": {
							const r = checkpointWAL();
							return r.checkpointed
								? `WAL checkpointed (${r.walSize} pages).`
								: "Checkpoint failed or busy.";
						}
						case "vacuum":
							return vacuumDatabase() ? "Vacuumed." : "Vacuum failed.";
						case "capture-stats":
							return JSON.stringify(getCaptureStats(), null, 2);
						case "distill-now": {
							const sid = ctx?.sessionID;
							if (!sid) return "Error: No session ID.";
							const did = distillSession(sid);
							return did
								? `Distillation #${did} created.`
								: "Not enough undistilled messages.";
						}
						case "curate-now": {
							const r = curateFromDistillations();
							return `Created ${r.created}, skipped ${r.skipped}. Patterns: ${JSON.stringify(r.patterns)}`;
						}
						case "lint": {
							const result = lintMemory({ staleDays: olderThanDays });

							// Entity graph contradiction scan
							const graphStats = getEntityGraphStats();
							if (graphStats.total_triples > 0) {
								try {
									// Check each active triple for contradictions
									const db = getMemoryDB();
									const activeTriples = db.query(
										"SELECT DISTINCT subject, predicate, object FROM entity_triples WHERE valid_to IS NULL LIMIT 200"
									).all() as { subject: string; predicate: string; object: string }[];
									for (const t of activeTriples) {
										const contradictions = findGraphContradictions(t.subject, t.predicate, t.object);
										if (contradictions.length > 0) {
											result.issues.push({
												severity: "medium" as const,
												title: `Graph contradiction: ${t.subject} ↔ ${t.object}`,
												detail: `Active triple "${t.subject} —[${t.predicate}]→ ${t.object}" has ${contradictions.length} conflicting predicate(s): ${contradictions.map(c => c.predicate).join(", ")}`,
												suggestion: `Use memory-graph-invalidate to close outdated triples`,
												type: "contradiction" as const,
												observation_ids: contradictions.map(c => c.source_observation_id).filter((id): id is number => id != null),
											});
										}
									}
								} catch { /* Graph table may not exist yet */ }
							}
							if (result.issues.length === 0) {
								return `Memory lint: clean (${result.stats.total_observations} observations, 0 issues).`;
							}
							const lines: string[] = [
								`## Memory Lint Report\n`,
								`**${result.issues.length} issues** found in ${result.stats.total_observations} observations:\n`,
								`| Duplicates | Contradictions | Stale | Orphans | Missing Narrative |`,
								`|---|---|---|---|---|`,
								`| ${result.stats.duplicates} | ${result.stats.contradictions} | ${result.stats.stale} | ${result.stats.orphans} | ${result.stats.missing_narrative} |\n`,
							];
							for (const issue of result.issues.slice(0, 15)) {
								lines.push(`- **[${issue.severity}]** ${issue.title}`);
								lines.push(`  ${issue.detail}`);
								lines.push(`  _Suggestion: ${issue.suggestion}_\n`);
							}
							if (result.issues.length > 15) {
								lines.push(`... and ${result.issues.length - 15} more issues.`);
							}
							return lines.join("\n");
						}
						case "index": {
							const result = generateMemoryIndex();
							return `Index generated: ${result.entryCount} observations, ${result.conceptCount} concepts. Read with \`memory-read({ file: "index" })\`.`;
						}
						case "compile": {
							const result = compileObservations();
							if (result.articles.length === 0) {
								return `No concept clusters with 3+ observations found. Nothing to compile.`;
							}
							const articleList = result.articles.map(a => `  - ${a.concept} (${a.observationCount} obs)`).join("\n");
							return `Compiled ${result.articles.length} articles from ${result.totalObservations} observations (${result.skippedClusters} skipped).\n\nArticles:\n${articleList}\n\nRead with \`memory-read({ file: "compiled/<concept>" })\`.`;
						}
						case "log": {
							return getLogContent();
						}
						case "migrate": {
							const obsDir = path.join(
								directory,
								".opencode",
								"memory",
								"observations",
							);
							let mdFiles: string[] = [];
							try {
								mdFiles = (await readdir(obsDir)).filter((f) =>
									f.endsWith(".md"),
								);
							} catch {
								return "No observations directory found.";
							}
							if (mdFiles.length === 0) return "No files to migrate.";
							const existing = new Set(getMarkdownFilesInSqlite());
							const toMigrate = args.force
								? mdFiles
								: mdFiles.filter((f) => !existing.has(f));
							if (toMigrate.length === 0) return "All files already migrated.";
							if (dryRun) return `Would migrate ${toMigrate.length} files.`;
							let migrated = 0;
							for (const file of toMigrate) {
								try {
									const content = await readFile(
										path.join(obsDir, file),
										"utf-8",
									);
									const fmMatch = content.match(
										/^---\n([\s\S]*?)\n---\n([\s\S]*)$/,
									);
									const body = fmMatch ? fmMatch[2].trim() : content.trim();
									const fm = fmMatch ? fmMatch[1] : "";
									storeObservation({
										type: (fm.match(/type:\s*(\w+)/)?.[1] ??
											"discovery") as ObservationType,
										title:
											fm.match(/title:\s*(.+)/)?.[1]?.trim() ??
											file.replace(/\.md$/, ""),
										narrative: body,
										confidence: (fm.match(/confidence:\s*(\w+)/)?.[1] ??
											"medium") as ConfidenceLevel,
										markdown_file: file,
										source: "imported",
									});
									migrated++;
								} catch {
									/* Skip failed files */
								}
							}
							if (migrated > 0) rebuildFTS5();
							return `Migrated ${migrated}/${toMigrate.length} files.`;
						}
						default:
							return `Unknown operation: "${op}".`;
					}
				} catch (err) {
					const message = err instanceof Error ? err.message : String(err);
					if (
						message.includes("database disk image is malformed") ||
						message.includes("SQLITE_CORRUPT") ||
						message.includes("integrity check failed")
					) {
						return (
							`Error: Memory database is corrupted. ` +
							`Automatic repair failed. Delete .opencode/memory.db to start fresh. Details: ${message}`
						);
					}
					return `Error: Admin operation failed: ${message}`;
				}
			},
		}),
	};
}
