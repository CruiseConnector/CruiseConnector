import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { processRouteSeedJobs } from "../tools/route_pool_healing_worker.ts";

type JsonMap = Record<string, unknown>;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  if (!isAuthorized(req)) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  let body: JsonMap = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  try {
    const result = await processRouteSeedJobs({
      jobLimit: intOption(
        body.max_jobs_per_run,
        "ROUTE_POOL_HEALING_MAX_JOBS_PER_RUN",
        2,
      ),
      maxGlobalMapboxCalls: intOption(
        body.max_mapbox_calls_per_run,
        "ROUTE_POOL_HEALING_MAX_MAPBOX_CALLS_PER_RUN",
        48,
      ),
      maxVerifiedPerClusterPerRun: intOption(
        body.max_verified_per_cluster_per_run,
        "ROUTE_POOL_HEALING_MAX_VERIFIED_PER_CLUSTER_PER_RUN",
        2,
      ),
      targetVerifiedPerJob: intOption(
        body.target_verified_per_job,
        "ROUTE_POOL_HEALING_TARGET_VERIFIED_PER_JOB",
        1,
      ),
      maxRuntimeSeconds: intOption(
        body.max_runtime_seconds,
        "ROUTE_POOL_HEALING_MAX_RUNTIME_SECONDS",
        90,
      ),
      edgeEndpoint: stringOption(
        body.route_generator_endpoint,
        "ROUTE_POOL_HEALING_GENERATOR_ENDPOINT",
      ),
    });
    return jsonResponse(result, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: "worker_failed", message }, 500);
  }
});

function isAuthorized(req: Request): boolean {
  const bearer = bearerToken(req.headers.get("authorization"));
  const cronSecret = Deno.env.get("ROUTE_POOL_HEALING_CRON_SECRET")?.trim();
  if (cronSecret && constantTimeEquals(bearer, cronSecret)) return true;
  if (
    cronSecret &&
    constantTimeEquals(req.headers.get("x-cron-secret"), cronSecret)
  ) {
    return true;
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  return serviceRoleKey != null && serviceRoleKey.length > 0 &&
    constantTimeEquals(bearer, serviceRoleKey);
}

function bearerToken(value: string | null): string {
  const trimmed = value?.trim() ?? "";
  return trimmed.toLowerCase().startsWith("bearer ")
    ? trimmed.slice("bearer ".length).trim()
    : "";
}

function intOption(
  value: unknown,
  envName: string,
  fallback: number,
): number {
  const raw = value ?? Deno.env.get(envName);
  const parsed = typeof raw === "number" ? raw : Number(String(raw ?? ""));
  return Number.isFinite(parsed) ? Math.floor(parsed) : fallback;
}

function stringOption(value: unknown, envName: string): string | undefined {
  const raw = typeof value === "string" ? value : Deno.env.get(envName);
  const trimmed = raw?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : undefined;
}

function constantTimeEquals(
  left: string | null,
  right: string | null,
): boolean {
  const a = new TextEncoder().encode(left ?? "");
  const b = new TextEncoder().encode(right ?? "");
  const length = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let index = 0; index < length; index += 1) {
    diff |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return diff === 0;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
}
