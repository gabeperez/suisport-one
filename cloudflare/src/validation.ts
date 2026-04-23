import { z } from "zod";
import type { Context } from "hono";
import type { Env, Variables } from "./env.js";

// Request body schemas. We validate every mutating route so malformed
// input fails at the edge with a 400 instead of corrupting D1.

export const AthletePatchSchema = z.object({
    displayName: z.string().min(1).max(40).optional(),
    handle: z.string().regex(/^[a-z0-9_]{2,24}$/).optional(),
    bio: z.string().max(200).nullable().optional(),
    location: z.string().max(60).nullable().optional(),
    avatarTone: z.string().max(20).optional(),
    bannerTone: z.string().max(20).optional(),
    photoR2Key: z.string().max(200).nullable().optional(),
});

export const KudosSchema = z.object({
    tip: z.number().int().min(0).max(100).optional().default(0),
});

export const CommentSchema = z.object({
    body: z.string().min(1).max(500),
});

export const ReportSchema = z.object({
    feedItemId: z.string().max(64).optional(),
    athleteId: z.string().max(80).optional(),
    reason: z.string().min(2).max(200),
});

export const CreateClubSchema = z.object({
    name: z.string().min(2).max(60),
    handle: z.string().regex(/^[a-z0-9_]{2,24}$/),
    tagline: z.string().max(120).optional(),
    description: z.string().max(500).optional(),
    heroTone: z.string().max(20).optional(),
    tags: z.array(z.string().max(30)).max(8).optional(),
});

export const AddShoeSchema = z.object({
    brand: z.string().min(1).max(40),
    model: z.string().min(1).max(40),
    nickname: z.string().max(40).nullable().optional(),
    tone: z.string().max(20).default("sunset"),
    milesTotal: z.number().min(100).max(5000).default(800),
});

export const SubmitWorkoutSchema = z.object({
    type: z.enum(["run", "walk", "ride", "hike", "swim", "lift", "yoga", "hiit", "other"]),
    startDate: z.number(),
    durationSeconds: z.number().min(1).max(48 * 3600),
    distanceMeters: z.number().min(0).max(500_000).nullable().optional(),
    energyKcal: z.number().min(0).max(20_000).nullable().optional(),
    avgHeartRate: z.number().min(0).max(240).nullable().optional(),
    paceSecondsPerKm: z.number().min(0).max(7200).nullable().optional(),
    points: z.number().int().min(0).max(10_000),
    title: z.string().min(1).max(80),
    caption: z.string().max(280).nullable().optional(),
});

export const AuthExchangeSchema = z.object({
    provider: z.enum(["google", "apple", "email"]),
    idToken: z.string().min(1).max(4096),
    displayName: z.string().max(40).optional(),
});

/// Helper: parse + 400 on invalid body. Returns the typed value.
export async function parseBody<T>(
    c: Context<{ Bindings: Env; Variables: Variables }>,
    schema: z.ZodType<T>
): Promise<T> {
    const raw = await c.req.json().catch(() => null);
    const res = schema.safeParse(raw);
    if (!res.success) {
        throw new ValidationError(res.error.issues);
    }
    return res.data;
}

export class ValidationError extends Error {
    issues: unknown;
    constructor(issues: unknown) {
        super("VALIDATION_ERROR");
        this.name = "ValidationError";
        this.issues = issues;
    }
}
