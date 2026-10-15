/** Register before transport starts, including EOF that arrives during startup. */
export function installLifecycle(cleanup: () => Promise<void>) {
  let closing: Promise<void> | undefined;
  const shutdown = (reason: string, code = 0): Promise<void> => {
    if (closing) return closing;
    closing = (async () => {
      process.stderr.write(`[moho-mcp] Shutdown: ${reason}\n`);
      // Keeps the loop alive during async cleanup, but leaves verified stale-owner
      // recovery to the next process if filesystem cleanup cannot finish.
      const timer = setTimeout(() => process.exit(1), 5000);
      try { await cleanup(); process.exitCode = code; }
      catch (error) { process.stderr.write(`[moho-mcp] Cleanup incomplete: ${String(error)}\n`); process.exitCode = 1; }
      finally { clearTimeout(timer); }
      process.exit(process.exitCode ?? code);
    })();
    return closing;
  };
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) process.on(signal, () => { void shutdown(signal); });
  for (const event of ["end", "close"] as const) process.stdin.on(event, () => { void shutdown(`stdin ${event}`); });
  process.stdin.on("error", () => { void shutdown("stdin error", 1); });
  process.stdout.on("error", () => { void shutdown("stdout error", 1); });
  process.on("disconnect", () => { void shutdown("parent disconnect"); });
  process.on("beforeExit", () => { void shutdown("event loop drained"); });
  return shutdown;
}
