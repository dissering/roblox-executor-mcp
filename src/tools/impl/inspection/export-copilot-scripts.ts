import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { sendAndWait, toolTextResponse, ToolOutputOptions } from "../../factory.js";
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

interface CopilotScriptItem {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
  queued: boolean;
  source: string;
}

interface CopilotBaseExportResult {
  scriptCount: number;
  scripts: CopilotScriptItem[];
  error?: string;
}

function writeExportManifest(dir: string, scripts: CopilotScriptItem[]): string {
  const manifest = {
    version: "1.0.0",
    exportedAt: new Date().toISOString(),
    scripts: scripts.map((s) => ({
      name: s.name,
      description: s.description,
      enabled: s.enabled,
      queued: s.queued,
      sourceLength: s.source.length,
    })),
  };
  const manifestPath = path.join(dir, "manifest.json");
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), "utf8");
  return manifestPath;
}

function writeReadme(dir: string, scripts: CopilotScriptItem[], repoName: string): string {
  let md = `# 🎮 ${repoName}\n\n`;
  md += `> Auto-exported from Copilot Chat Roblox scripting session\n`;
  md += `> Exported: ${new Date().toISOString()}\n\n`;
  md += `## 📋 Scripts\n\n`;

  if (scripts.length > 0) {
    md += `| Script | Description | Status | Source Length |\n`;
    md += `|--------|-------------|--------|---------------|\n`;
    for (const s of scripts) {
      const status = s.queued ? "⏸️ Queued" : s.enabled ? "▶️ Enabled" : "⏹️ Disabled";
      md += `| \`${s.name}\` | ${s.description} | ${status} | ${s.source.length} chars |\n`;
    }
    md += `\n**Total: ${scripts.length} script(s)**\n`;
  } else {
    md += `_No scripts exported._\n`;
  }

  md += `\n## 📖 How to Use\n\n`;
  md += `1. Copy a \`.luau\` file to your Roblox executor\n`;
  md += `2. Execute via Fluent GUI or directly\n`;
  md += `3. Scripts with Queued status need to be enabled in-game\n\n`;

  md += `## 🔄 Workflow\n\n`;
  md += `- Scripts are written in Copilot Chat via MCP tools\n`;
  md += `- Each script is created as a "feature" in Fluent GUI\n`;
  md += `- Scripts default to paused/queued until enabled\n`;
  md += `- Export to GitHub using the "Update to GitHub" button or MCP tool\n`;

  const readmePath = path.join(dir, "README.md");
  fs.writeFileSync(readmePath, md, "utf8");
  return readmePath;
}

export default function registerExportCopilotScripts(server: McpServer): void {
  server.registerTool(
    "export-copilot-scripts",
    {
      title: "Export Copilot Scripts",
      description:
        "Export all scripts from the CopilotBase (Fluent GUI base) on the active Roblox client. " +
        "Writes scripts to the scripts directory with manifest and README, then commits to git. " +
        "Use this to save chat-written scripts as a GitHub project.",
      inputSchema: z.object({
        outputDir: z
          .string()
          .describe(
            "Directory to write scripts to (relative to repo root). Defaults to ./scripts/roblox-automation-scripts"
          )
          .optional()
          .default("./scripts/roblox-automation-scripts"),
        commit: z
          .boolean()
          .describe("Whether to git commit after exporting")
          .optional()
          .default(true),
        push: z
          .boolean()
          .describe("Whether to git push after committing")
          .optional()
          .default(false),
        repoName: z
          .string()
          .describe("Repository name for the scripts collection")
          .optional()
          .default("copilot-roblox-scripts"),
      }),
    },
    async ({ outputDir, commit, push, repoName }: { outputDir: string; commit: boolean; push: boolean; repoName: string }) => {
      const outputOptions: ToolOutputOptions = {
        maxOutputChars: 32000,
        truncationHint: "Rerun export-copilot-scripts with commit=false to skip git operations.",
      };

      try {
        // Step 1: Query CopilotBase from executor via bridge
        const gatherCode = `
          local base = getgenv().CopilotBase
          if not base or not base.Scripts then
            return { scriptCount = 0, scripts = {}, error = "CopilotBase not found. Load fluent-base.luau first." }
          end

          local result = { scriptCount = 0, scripts = {} }

          for id, script in pairs(base.Scripts) do
            result.scriptCount = result.scriptCount + 1
            table.insert(result.scripts, {
              id = script.Id or id,
              name = script.Name or script.Id or id,
              description = script.Description or "No description",
              enabled = script.Enabled or false,
              queued = script.Queued or false,
              source = script.OnEnable or "",
            })
          end

          return result
        `;

        // Query executor via bridge using the existing get-data-by-code type
        const response = await sendAndWait({
          type: "get-data-by-code",
          data: { source: gatherCode, threadContext: 8 },
          timeoutMs: 15000,
          maxOutputChars: 32000,
          stampClient: true,
          truncationHint: "Rerun with fewer scripts or smaller source.",
          failureMessage: (resp) => "Failed to query CopilotBase: " + String(resp?.error || resp?.output || "unknown"),
        });

        // Parse the result - the bridge returns serialized JSON
        let scriptData: CopilotBaseExportResult;
        try {
          // The response text should contain the serialized Lua table as JSON
          // Extract JSON from the response
          const text = response.content[0]?.text || "";
          // Try to find JSON object in the response
          const jsonMatch = text.match(/\{[\s\S]*"scriptCount"[\s\S]*\}/);
          if (!jsonMatch) {
            throw new Error("No JSON found in response. Response: " + text.slice(0, 500));
          }
          scriptData = JSON.parse(jsonMatch[0]);
        } catch (e) {
          return toolTextResponse(
            `Failed to parse executor response: ${e}. Response was: ${response.content[0]?.text?.slice(0, 500)}`,
            outputOptions,
            true,
          );
        }

        if (scriptData.error) {
          return toolTextResponse(`Export failed: ${scriptData.error}`, outputOptions, true);
        }

        const scripts = scriptData.scripts || [];

        if (scripts.length === 0) {
          return toolTextResponse(
            "No scripts found in CopilotBase. Add features using Base:AddFeatureToggle or Base:CreateFeature first.",
            outputOptions,
          );
        }

        // Step 2: Write scripts to output directory
        const absOutputDir = path.resolve(outputDir);
        const scriptsDir = path.join(absOutputDir, "scripts");
        fs.mkdirSync(scriptsDir, { recursive: true });

        const writtenFiles: string[] = [];
        for (const script of scripts) {
          const safeName = script.name.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 50);
          const scriptPath = path.join(scriptsDir, `${safeName}.luau`);

          let content = script.source || `-- Script: ${safeName}\nprint("Script loaded")\n`;

          // Add metadata header
          let header = `-- ⚠️ Auto-exported from Copilot Chat\n`;
          header += `-- Script: ${safeName}\n`;
          header += `-- Description: ${script.description}\n`;
          header += `-- Exported: ${new Date().toISOString()}\n`;
          header += `-- Queued: ${script.queued}\n`;
          header += `-- ═══════════════════════════════════════\n\n`;

          fs.writeFileSync(scriptPath, header + content, "utf8");
          writtenFiles.push(path.relative(process.cwd(), scriptPath));
        }

        // Step 3: Write manifest and README
        writeExportManifest(absOutputDir, scripts);
        writeReadme(absOutputDir, scripts, repoName);

        // Step 4: Git commit and push
        let gitOutput = "";
        if (commit) {
          try {
            const gitAdd = execSync(`git add -A "${outputDir}"`, {
              encoding: "utf8",
              cwd: process.cwd(),
            });
            const gitCommit = execSync(
              `git commit -m "feat: export ${scripts.length} CopilotBase script(s) to ${repoName}"`,
              {
                encoding: "utf8",
                cwd: process.cwd(),
              },
            );
            gitOutput = gitCommit;

            if (push) {
              const gitPush = execSync("git push", {
                encoding: "utf8",
                cwd: process.cwd(),
              });
              gitOutput += "\n" + gitPush;
            }
          } catch (err) {
            const gitErr = err as Error;
            if (gitErr.message && gitErr.message.includes("nothing to commit")) {
              gitOutput = "(No new changes to commit)";
            } else {
              gitOutput = "Git error (scripts still written): " + gitErr.message;
            }
          }
        }

        return toolTextResponse(
          JSON.stringify(
            {
              status: "success",
              scriptsExported: scripts.length,
              writtenFiles,
              gitCommit: gitOutput,
              outputDir,
              message: `Exported ${scripts.length} script(s) to ${outputDir}`,
            },
            null,
            2,
          ),
          outputOptions,
        );
      } catch (error) {
        return toolTextResponse(
          `Export failed: ${(error as Error).message}`,
          outputOptions,
          true,
        );
      }
    },
  );
}
