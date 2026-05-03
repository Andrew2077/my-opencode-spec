/**
 * Compact Format — AAAK-Inspired Memory Compression (v3)
 *
 * Inspired by MemPalace's AAAK dialect: a symbolic, pipe-separated format
 * achieving ~3-5x compression while remaining readable by any LLM.
 *
 * Used for L1 wake-up context: compress top observations into a dense
 * format that fits in ~200-300 tokens instead of 800+.
 *
 * Format rules:
 * - Entities: 3-letter uppercase codes (ALC=Alice, KAI=Kai)
 * - Categories: UPPERCASE labels (DECISION, PATTERN, WARNING)
 * - Relationships: arrow notation (→, ←, ↔)
 * - Importance: 1-5 stars (★ to ★★★★★)
 * - Dates: ISO short (2026-03-31)
 * - Pipe-separated fields within lines
 */

import type { CompactResult } from "./db/types.js";

// ============================================================================
// Entity Code Generation
// ============================================================================

/**
 * Generate a 3-letter uppercase code from a name.
 * Prioritizes: first 3 consonants, then first 3 chars.
 */
function generateCode(name: string): string {
	const cleaned = name.replace(/[^a-zA-Z]/g, "").toUpperCase();
	const consonants = cleaned.replace(/[AEIOU]/g, "");
	if (consonants.length >= 3) return consonants.slice(0, 3);
	return cleaned.slice(0, 3).padEnd(3, "X");
}

/**
 * Build entity code map from observation data.
 * Deduplicates codes by appending numbers.
 */
function buildCodeMap(names: string[]): Map<string, string> {
	const codeMap = new Map<string, string>();
	const usedCodes = new Set<string>();

	for (const name of names) {
		let code = generateCode(name);
		if (usedCodes.has(code)) {
			// Append incrementing suffix
			let i = 2;
			while (usedCodes.has(`${code.slice(0, 2)}${i}`)) i++;
			code = `${code.slice(0, 2)}${i}`;
		}
		usedCodes.add(code);
		codeMap.set(name.toLowerCase(), code);
	}

	return codeMap;
}

// ============================================================================
// Observation Type Mapping
// ============================================================================

const TYPE_LABELS: Record<string, string> = {
	decision: "DECISION",
	bugfix: "FIX",
	feature: "FEAT",
	pattern: "PATTERN",
	discovery: "DISC",
	learning: "LEARN",
	warning: "WARN",
};

const CONFIDENCE_STARS: Record<string, string> = {
	high: "★★★",
	medium: "★★",
	low: "★",
};

// ============================================================================
// Compact Compression
// ============================================================================

interface ObservationSummary {
	id: number;
	type: string;
	title: string;
	narrative?: string | null;
	concepts?: string | null;
	wing?: string | null;
	hall?: string | null;
	room?: string | null;
	confidence?: string | null;
	created_at?: string | null;
}

/**
 * Compress an array of observations into compact AAAK-inspired format.
 * Returns compressed text + compression metrics.
 */
export function compactObservations(
	observations: ObservationSummary[],
): CompactResult {
	if (observations.length === 0) {
		return {
			compressed: "",
			token_estimate: 0,
			original_tokens: 0,
			compression_ratio: 0,
		};
	}

	// Estimate original size
	const originalText = observations
		.map(
			(o) =>
				`[${o.type}] ${o.title}: ${o.narrative ?? ""} (${o.concepts ?? ""})`,
		)
		.join("\n");
	const originalTokens = Math.ceil(originalText.length / 4);

	// Collect entities for code generation
	const entities: string[] = [];
	for (const obs of observations) {
		if (obs.wing) entities.push(obs.wing);
		if (obs.room) entities.push(obs.room);
	}
	const codeMap = buildCodeMap([...new Set(entities)]);

	// Group by type
	const grouped = new Map<string, ObservationSummary[]>();
	for (const obs of observations) {
		const key = obs.type;
		const existing = grouped.get(key) ?? [];
		existing.push(obs);
		grouped.set(key, existing);
	}

	// Build compact lines
	const lines: string[] = [];

	// Header: entity legend (if entities exist)
	if (codeMap.size > 0) {
		const legend = [...codeMap.entries()]
			.map(([name, code]) => `${code}=${name}`)
			.join(" ");
		lines.push(`ENTITIES: ${legend}`);
	}

	// Observations grouped by type
	for (const [type, obs] of grouped) {
		const label = TYPE_LABELS[type] ?? type.toUpperCase();
		const entries = obs.map((o) => {
			const parts: string[] = [];

			// Title (abbreviated)
			const shortTitle =
				o.title.length > 60 ? `${o.title.slice(0, 57)}...` : o.title;
			parts.push(shortTitle);

			// Navigation context
			if (o.wing || o.room) {
				const nav: string[] = [];
				if (o.wing) nav.push(codeMap.get(o.wing.toLowerCase()) ?? o.wing);
				if (o.room) nav.push(codeMap.get(o.room.toLowerCase()) ?? o.room);
				parts.push(`@${nav.join("/")}`);
			}

			// Confidence
			if (o.confidence) {
				parts.push(CONFIDENCE_STARS[o.confidence] ?? "★★");
			}

			// Date
			if (o.created_at) {
				parts.push(o.created_at.slice(0, 10));
			}

			return parts.join(" | ");
		});

		lines.push(`${label}: ${entries.join(" // ")}`);
	}

	const compressed = lines.join("\n");
	const compressedTokens = Math.ceil(compressed.length / 4);

	return {
		compressed,
		token_estimate: compressedTokens,
		original_tokens: originalTokens,
		compression_ratio:
			originalTokens > 0 ? compressedTokens / originalTokens : 0,
	};
}
