import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { describeResponse, sendAndWait } from "../../factory.js";
import { maxOutputCharsSchema } from "../../schemas.js";

const directionSchema = z.enum(["Incoming", "Outgoing"]);

const inputSchema = z.discriminatedUnion("operation", [
  z.object({
    operation: z.literal("list"),
    direction: z
      .enum(["Incoming", "Outgoing", "Both"])
      .describe("Call direction to inspect (default: Both)")
      .optional()
      .default("Both"),
    nameFilter: z
      .string()
      .describe("Case-insensitive substring filter for remote names")
      .optional(),
    limit: z
      .number()
      .describe("Maximum remote entries to return (default: 5, max: 100)")
      .optional()
      .default(5),
    maxCallsPerRemote: z
      .number()
      .describe("Recent calls to include per remote when summaryOnly is false (default: 1, max: 20)")
      .optional()
      .default(1),
    summaryOnly: z
      .boolean()
      .describe("Return names, state, and call counts without argument payloads (default: true)")
      .optional()
      .default(true),
    maxOutputChars: maxOutputCharsSchema,
  }),
  z.object({ operation: z.literal("clear") }),
  z.object({ operation: z.literal("status") }),
  z.object({
    operation: z.enum(["block", "unblock", "ignore", "unignore"]),
    remoteName: z
      .string()
      .describe("Exact remote name. Rules also apply to remotes that have not fired yet"),
    direction: directionSchema.describe("Direction the rule applies to"),
  }),
  z.object({
    operation: z.literal("configure"),
    enabled: z.boolean().describe("Pause (false) or resume (true) logging and blocking").optional(),
    includeBindables: z
      .boolean()
      .describe("Also log BindableEvent:Fire and BindableFunction:Invoke (default: false)")
      .optional(),
    includeExecutorCalls: z
      .boolean()
      .describe("Also log and block calls made by executor scripts, including replays (default: false)")
      .optional(),
  }),
]);

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
      const maxOutputChars = input.operation === "list" ? input.maxOutputChars : undefined;
      return sendAndWait({
        type: "remote-spy",
        data: input,
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
