import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { describeResponse, sendAndWait } from "../../factory.js";

export default function register(server: McpServer): void {
  server.registerTool(
    "click-button",
    {
      title: "Click a GuiButton",
      description:
        "Click a Roblox TextButton or ImageButton via firesignal, or a virtual mouse click when firesignal is absent. The fallback requires a visible, unobstructed button and VirtualInputManager permission.",
      inputSchema: z.object({
        path: z.string().describe("The instance path to the Button"),
        action: z
          .string()
          .describe(
            "The signal to fire. Without firesignal, only Activated, MouseButton1Click, MouseButton2Click or an omitted action support a virtual click; down-only signals require firesignal."
          )
          .optional(),
      }),
    },
    async ({ path, action }) =>
      sendAndWait({
        type: "click-button",
        data: { path, action },
        failureField: "error",
        failureMessage: (response) =>
          "Failed to click Button: " + describeResponse(response),
        successMessage: (response) =>
          (response.output as string | undefined) || "Successfully fired click signals on Button.",
      })
  );
}
