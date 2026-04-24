const DEBUG_LOG_ENABLED = Deno.env.get("DEBUG_LOG") === "true";

function sanitizeLogValue(value: unknown): unknown {
  if (typeof value === "string") {
    return value
      .replace(/access_token=[^&\s]+/gi, "access_token=[redacted]")
      .replace(
        /(mapbox[a-z0-9._-]*token[^:=\s]*\s*[:=]\s*)[^\s,}]+/gi,
        "$1[redacted]",
      );
  }
  if (Array.isArray(value)) {
    return value.map((entry) => sanitizeLogValue(entry));
  }
  if (value && typeof value === "object") {
    const sanitized: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value)) {
      const lowerKey = key.toLowerCase();
      sanitized[key] = lowerKey.includes("token") || lowerKey.includes("secret")
        ? "[redacted]"
        : sanitizeLogValue(entry);
    }
    return sanitized;
  }
  return value;
}

function sanitizeLogArgs(args: unknown[]): unknown[] {
  return args.map((arg) => sanitizeLogValue(arg));
}

export function debugLog(...args: unknown[]): void {
  if (!DEBUG_LOG_ENABLED) return;
  console.log(...sanitizeLogArgs(args));
}

export function debugWarn(...args: unknown[]): void {
  if (!DEBUG_LOG_ENABLED) return;
  console.warn(...sanitizeLogArgs(args));
}

export function debugError(...args: unknown[]): void {
  if (!DEBUG_LOG_ENABLED) return;
  console.error(...sanitizeLogArgs(args));
}
