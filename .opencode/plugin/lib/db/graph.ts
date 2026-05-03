/**
 * Entity Graph Operations (v3)
 *
 * Temporal knowledge graph backed by SQLite entity_triples table.
 * Supports time-aware queries (as_of), invalidation, and entity timeline.
 *
 * Inspired by MemPalace's temporal KG pattern: facts have valid_from/valid_to
 * dates, enabling "what was true on date X?" queries.
 */

import { getMemoryDB } from "./schema.js";
import type {
	EntityQueryResult,
	EntityTripleInput,
	EntityTripleRow,
} from "./types.js";

// ============================================================================
// CRUD
// ============================================================================

/**
 * Add a new entity triple to the knowledge graph.
 */
export function addEntityTriple(input: EntityTripleInput): number {
	const db = getMemoryDB();
	const now = new Date();

	const validFrom = input.valid_from ?? now.toISOString().slice(0, 10);

	const result = db
		.query(
			`INSERT INTO entity_triples
       (subject, predicate, object, valid_from, valid_to, confidence, source_observation_id, created_at, created_at_epoch)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		)
		.run(
			input.subject.toLowerCase().trim(),
			input.predicate.toLowerCase().trim(),
			input.object.toLowerCase().trim(),
			validFrom,
			input.valid_to ?? null,
			input.confidence ?? 1.0,
			input.source_observation_id ?? null,
			now.toISOString(),
			now.getTime(),
		);

	return Number(result.lastInsertRowid);
}

/**
 * Invalidate a triple by setting its valid_to date.
 * Finds active triples matching subject+predicate+object and closes them.
 */
export function invalidateTriple(
	subject: string,
	predicate: string,
	object: string,
	endDate?: string,
): number {
	const db = getMemoryDB();
	const validTo = endDate ?? new Date().toISOString().slice(0, 10);

	const result = db.run(
		`UPDATE entity_triples
     SET valid_to = ?
     WHERE LOWER(subject) = LOWER(?) AND LOWER(predicate) = LOWER(?) AND LOWER(object) = LOWER(?)
       AND valid_to IS NULL`,
		[validTo, subject.trim(), predicate.trim(), object.trim()],
	);

	return result.changes;
}

/**
 * Get a triple by ID.
 */
export function getTripleById(id: number): EntityTripleRow | null {
	const db = getMemoryDB();
	return db
		.query("SELECT * FROM entity_triples WHERE id = ?")
		.get(id) as EntityTripleRow | null;
}

// ============================================================================
// Queries
// ============================================================================

/**
 * Query entity relationships with optional time filtering.
 * Returns triples where entity appears as subject or object.
 */
export function queryEntity(
	entity: string,
	options: {
		as_of?: string; // ISO date — filter to triples valid at this time
		direction?: "out" | "in" | "both"; // out = subject, in = object, both = either
		predicate?: string; // filter by predicate
		activeOnly?: boolean; // only return currently active triples
		limit?: number;
	} = {},
): EntityQueryResult[] {
	const db = getMemoryDB();
	const direction = options.direction ?? "both";
	const limit = options.limit ?? 50;
	const entityLower = entity.toLowerCase().trim();

	const conditions: string[] = [];
	const params: (string | number)[] = [];

	// Direction filter
	if (direction === "out") {
		conditions.push("LOWER(subject) = ?");
		params.push(entityLower);
	} else if (direction === "in") {
		conditions.push("LOWER(object) = ?");
		params.push(entityLower);
	} else {
		conditions.push("(LOWER(subject) = ? OR LOWER(object) = ?)");
		params.push(entityLower, entityLower);
	}

	// Predicate filter
	if (options.predicate) {
		conditions.push("LOWER(predicate) = ?");
		params.push(options.predicate.toLowerCase().trim());
	}

	// Time filter
	if (options.as_of) {
		conditions.push("valid_from <= ?");
		params.push(options.as_of);
		conditions.push("(valid_to IS NULL OR valid_to >= ?)");
		params.push(options.as_of);
	} else if (options.activeOnly) {
		conditions.push("valid_to IS NULL");
	}

	params.push(limit);

	const sql = `
    SELECT id, subject, predicate, object, valid_from, valid_to, confidence,
           CASE WHEN valid_to IS NULL THEN 1 ELSE 0 END as is_active
    FROM entity_triples
    WHERE ${conditions.join(" AND ")}
    ORDER BY valid_from DESC, created_at_epoch DESC
    LIMIT ?
  `;

	return db.query(sql).all(...params) as EntityQueryResult[];
}

/**
 * Get entity timeline — all triples involving an entity, sorted chronologically.
 */
export function getEntityTimeline(
	entity: string,
	options: { limit?: number } = {},
): EntityTripleRow[] {
	const db = getMemoryDB();
	const limit = options.limit ?? 100;
	const entityLower = entity.toLowerCase().trim();

	return db
		.query(
			`SELECT * FROM entity_triples
       WHERE LOWER(subject) = ? OR LOWER(object) = ?
       ORDER BY valid_from ASC, created_at_epoch ASC
       LIMIT ?`,
		)
		.all(entityLower, entityLower, limit) as EntityTripleRow[];
}

/**
 * Find contradictions: active triples with opposing predicates for same subject-object pair.
 */
export function findContradictions(
	subject: string,
	predicate: string,
	object: string,
): EntityTripleRow[] {
	const db = getMemoryDB();

	return db
		.query(
			`SELECT * FROM entity_triples
       WHERE LOWER(subject) = LOWER(?) AND LOWER(object) = LOWER(?)
         AND LOWER(predicate) != LOWER(?)
         AND valid_to IS NULL
       ORDER BY created_at_epoch DESC`,
		)
		.all(subject.trim(), object.trim(), predicate.trim()) as EntityTripleRow[];
}

// ============================================================================
// Stats
// ============================================================================

/**
 * Get entity graph statistics.
 */
export function getEntityGraphStats(): {
	total_triples: number;
	active_triples: number;
	unique_entities: number;
	unique_predicates: number;
} {
	const db = getMemoryDB();

	const total = (
		db.query("SELECT COUNT(*) as count FROM entity_triples").get() as {
			count: number;
		}
	).count;

	const active = (
		db
			.query(
				"SELECT COUNT(*) as count FROM entity_triples WHERE valid_to IS NULL",
			)
			.get() as {
			count: number;
		}
	).count;

	const entities = (
		db
			.query(
				`SELECT COUNT(DISTINCT entity) as count FROM (
           SELECT subject as entity FROM entity_triples
           UNION ALL
           SELECT object as entity FROM entity_triples
         )`,
			)
			.get() as { count: number }
	).count;

	const predicates = (
		db
			.query("SELECT COUNT(DISTINCT predicate) as count FROM entity_triples")
			.get() as {
			count: number;
		}
	).count;

	return {
		total_triples: total,
		active_triples: active,
		unique_entities: entities,
		unique_predicates: predicates,
	};
}
