import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { sendAndWait } from "../../factory.js";
import { maxOutputCharsSchema } from "../../schemas.js";

export default function register(server: McpServer): void {
  server.registerTool(
    "get-game-info",
    {
      title: "Get information about the current Roblox game",
      description:
        "Get current Roblox place/universe metadata and executor capability availability. Function availability is not a guarantee of sUNC compliance or elevated permissions.",
      inputSchema: z.object({
        includeDescription: z
          .boolean()
          .describe("When true, include the (potentially long) place description text. Off by default to keep output small.")
          .optional()
          .default(false),
        maxOutputChars: maxOutputCharsSchema,
      }),
    },
    async ({ includeDescription, maxOutputChars }) =>
      sendAndWait({
        type: "get-game-info",
        data: { includeDescription },
        maxOutputChars,
        stampClient: true,
        failureMessage: () => "Failed to get game info.",
      })
  );
}
