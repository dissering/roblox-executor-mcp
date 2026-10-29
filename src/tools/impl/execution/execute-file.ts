import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import fs from "fs";
import { z } from "zod";
import { sendFireAndForget, toolTextResponse } from "../../factory.js";
import { threadContextSchema } from "../../schemas.js";

export default function register(server: McpServer): void {
  server.registerTool(
    "execute-file",
    {
      title: "Execute a Luau file in the Roblox Game Client",
      description:
        "Execute a local .luau or .lua file in the active Roblox client without returning output. Use get-data-by-code instead when you need returned values. To verify the effect, follow up with a small get-console-output (low limit) or a targeted get-data-by-code probe.",
      inputSchema: z.object({
        filePath: z
          .string()
          .describe("The absolute path to the .luau or .lua file to execute"),
        threadContext: threadContextSchema,
      }),
    },
    async ({ filePath, threadContext }) => {
      if (!fs.existsSync(filePath)) {
        return toolTextResponse(`File not found: ${filePath}`, {}, true);
      }

      const code = fs.readFileSync(filePath, "utf-8");
      console.error(`Executing file ${filePath} in thread ${threadContext}...`);

      return sendFireAndForget({
        type: "execute",
        data: { source: code, threadContext },
        successMessage: `File scheduled: ${filePath} (requested thread context ${threadContext}; uses existing permissions if unsupported).`,
      });
    }
  );
}
