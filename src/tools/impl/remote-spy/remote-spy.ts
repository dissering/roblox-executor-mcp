import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { describeResponse, sendAndWait } from "../../factory.js";
import { maxOutputCharsSchema } from "../../schemas.js";

// A flat object (not a discriminated union) so MCP clients receive a real JSON Schema
// with every parameter. Operation-specific requirements are checked in the handler.
const inputSchema = z.object({
  operation: z
    .enum(["status", "list", "clear", "block", "unblock", "ignore", "unignore", "configure"])
    .describe(
      "status: active modes and rules. list: logged remotes. clear: drop logs (rules stay). " +
        "block/unblock, ignore/unignore: rule for remoteName + direction. configure: change spy settings."
    ),
  direction: z
    .enum(["Incoming", "Outgoing", "Both"])
    .describe("list: direction to show (default Both). block/ignore: Incoming or Outgoing (required)")
    .optional(),
  nameFilter: z.string().describe("list: case-insensitive substring filter on remote names").optional(),
  limit: z.number().describe("list: maximum remotes to return (default 5, max 100)").optional(),
  maxCallsPerRemote: z
    .number()
    .describe("list: recent calls per remote when summaryOnly is false (default 1, max 20)")
    .optional(),
  summaryOnly: z
    .boolean()
    .describe("list: names, state and counts only, without arguments (default true)")
    .optional(),
  remoteName: z
    .string()
    .describe("block/unblock/ignore/unignore: exact remote name. Applies before the remote first fires")
    .optional(),
  enabled: z.boolean().describe("configure: pause (false) or resume (true) the spy").optional(),
  includeBindables: z
    .boolean()
    .describe("configure: also log BindableEvent:Fire and BindableFunction:Invoke (default false)")
    .optional(),
  includeExecutorCalls: z
    .boolean()
    .describe("configure: also log and block calls from executor scripts, including replays (default false)")
    .optional(),
  maxOutputChars: maxOutputCharsSchema,
});

type RemoteSpyInput = z.infer<typeof inputSchema>;

function validate(input: RemoteSpyInput): string | null {
  const rule = ["block", "unblock", "ignore", "unignore"].includes(input.operation);
  if (rule && !input.remoteName) return `remoteName is required for operation=${input.operation}.`;
  if (rule && input.direction !== "Incoming" && input.direction !== "Outgoing") {
    return `direction must be Incoming or Outgoing for operation=${input.operation}.`;
  }
  return null;
}

function withListDefaults(input: RemoteSpyInput): Record<string, unknown> {
  if (input.operation !== "list") return { ...input };
  return {
    ...input,
    direction: input.direction ?? "Both",
    limit: input.limit ?? 5,
    maxCallsPerRemote: input.maxCallsPerRemote ?? 1,
    summaryOnly: input.summaryOnly ?? true,
  };
}

export default function register(server: McpServer): void {
  server.registerTool(
    "remote-spy",
    {
      title: "Inspect and control the remote spy",
      description:
        "Built-in remote spy; it starts automatically on first use. Outgoing FireServer/InvokeServer calls are captured with the strongest hook the executor supports (namecall hook, raw metatable, or hookfunction). Incoming OnClientEvent traffic is logged on every executor, including ones without hooks. Call operation=status to see which modes are active. Use operation=list with summaryOnly=true and small limits first; with summaryOnly=false each recent call includes its arguments, calling script, and a Replay snippet you can pass to execute. block/unblock drops or allows matching calls (incoming blocking needs getconnections); ignore/unignore only stops logging. Rules match exact remote names and apply before a remote first fires. configure pauses the spy or includes bindables or executor calls.",
      inputSchema,
    },
    async (input) => {
      const problem = validate(input);
      if (problem) {
        return { content: [{ type: "text" as const, text: problem }], isError: true };
      }
      const maxOutputChars = input.operation === "list" ? input.maxOutputChars : undefined;
      return sendAndWait({
        type: "remote-spy",
        data: withListDefaults(input),
        maxOutputChars,
        stampClient: true,
        truncationHint:
          "Rerun remote-spy list with summaryOnly=true, a nameFilter, a lower limit, or fewer calls per remote.",
        failureMessage: (response) =>
          "Failed to use remote spy: " + describeResponse(response),
      });
    }
  );
}
