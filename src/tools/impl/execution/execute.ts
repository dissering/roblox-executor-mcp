import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { sendFireAndForget } from "../../factory.js";
import { threadContextSchema } from "../../schemas.js";

export default function register(server: McpServer): void {
  server.registerTool(
    "execute",
    {
      title: "Execute Code in the Roblox Game Client",
      description:
        "Execute Luau in the active Roblox client without returning output. Use get-data-by-code instead when you need returned values. To verify the effect, follow up with a small get-console-output (low limit) or a targeted get-data-by-code probe.",
      inputSchema: z.object({
        code: z
          .string()
          .describe(
            "The code to execute in the Roblox Game Client. This tool does NOT return output - use get-data-by-code if you need to retrieve data."
          ),
        threadContext: threadContextSchema,
      }),
    },
    async ({ code, threadContext }) => {
      console.error(`Executing code in thread ${threadContext}...`);
      return sendFireAndForget({
        type: "execute",
        data: { source: code, threadContext },
        successMessage: `Code scheduled (requested thread context ${threadContext}; uses existing permissions if unsupported).`,
      });
    }
  );
}
