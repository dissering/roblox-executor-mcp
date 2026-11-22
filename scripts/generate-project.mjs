#!/usr/bin/env node
// scripts/generate-project.mjs
// Generate a Roblox scripts project structure and push to GitHub

import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

const args = process.argv.slice(2);
const help = () => {
  console.log(`
Usage: node scripts/generate-project.mjs [options]

Options:
  --repo <owner/repo>     Target GitHub repository (default: use git remote)
  --output <path>         Output directory (default: ./scripts/<repo-name>)
  --description <text>    Project description
  --public                Create as public repo
  --list                  List available scripts from stdin (JSON)
  --push                  Git push after generating

Examples:
  node scripts/generate-project.mjs --repo dawid-scripts/Fluent --output scripts/Fluent
  node scripts/generate-project.mjs --list < scripts.json
  node scripts/generate-project.mjs --repo owner/repo --push
`);
  process.exit(0);
};

// Parse args
let repo = null;
let outputPath = null;
let description = "Roblox game scripts generated from chat";
let shouldPush = false;
let listMode = false;

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--repo" && i + 1 < args.length) {
    repo = args[++i];
  } else if (args[i] === "--output" && i + 1 < args.length) {
    outputPath = args[++i];
  } else if (args[i] === "--description" && i + 1 < args.length) {
    description = args[++i];
  } else if (args[i] === "--public") {
    // Flag for future use (project creation via API)
  } else if (args[i] === "--list") {
    listMode = true;
  } else if (args[i] === "--push") {
    shouldPush = true;
  } else if (args[i] === "--help" || args[i] === "-h") {
    help();
  }
}

// Get git remote
function getRemoteUrl() {
  try {
    const output = execSync("git remote get-url origin", {
      encoding: "utf8",
      cwd: process.cwd(),
    }).trim();
    // Convert git@github.com:owner/repo.git to owner/repo
    if (output.startsWith("git@github.com:")) {
      return output
        .replace("git@github.com:", "")
        .replace(".git", "")
        .replace(/\//g, "/");
    }
    if (output.includes("github.com")) {
      const match = output.match(/github\.com[/:](.+?)\.git$/);
      return match ? match[1] : output;
    }
    return output;
  } catch {
    return null;
  }
}

// Get repo from remote if not specified
if (!repo) {
  repo = getRemoteUrl();
  if (!repo) {
    console.error("Error: No --repo specified and no GitHub remote found.");
    process.exit(1);
  }
}

// Validate repo format
const repoMatch = repo.match(/^([\w-]+)\/([\w.-]+)$/);
if (!repoMatch) {
  console.error(`Error: Invalid repo format "${repo}". Expected "owner/repo".`);
  process.exit(1);
}
const [_, owner, repoName] = repoMatch;

// Output directory
if (!outputPath) {
  outputPath = path.join(process.cwd(), "scripts", repoName);
} else {
  outputPath = path.resolve(outputPath);
}

// Read scripts from stdin
async function readScriptsFromStdin() {
  return new Promise((resolve) => {
    const chunks = [];
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => chunks.push(chunk));
    process.stdin.on("end", () => {
      try {
        const scripts = JSON.parse(chunks.join(""));
        resolve(Array.isArray(scripts) ? scripts : []);
      } catch {
        resolve([]);
      }
    });
    // Timeout after 2 seconds of no input
    setTimeout(() => resolve([]), 2000);
  });
}

// Default script metadata
function defaultScriptMeta(name) {
  return {
    name,
    description: `Script: ${name}`,
    author: "Copilot Chat",
    version: "1.0.0",
    enabled: false, // Scripts start paused
  };
}

// Generate README for the scripts collection
function generateReadme(repoInfo, scripts) {
  const { owner, repoName, scriptsList = [] } = repoInfo;
  let md = `# 🎮 Roblox Scripts — ${repoName}\n\n`;
  md += `> Generated from Copilot Chat conversations\n`;
  md += `> Repository: [${owner}/${repoName}](https://github.com/${owner}/${repoName})\n\n`;

  md += `## 📋 Scripts\n\n`;
  if (scriptsList.length > 0) {
    md += `| Script | Description | Status | Author |\n`;
    md += `|--------|-------------|--------|--------|\n`;
    for (const s of scriptsList) {
      md += `| \`${s.name || s.id}\` | ${s.description || "N/A"} | ${s.paused ? "⏸️ Paused" : "▶️ Ready"} | ${s.author || "Copilot"} |\n`;
    }
  } else {
    md += `_No scripts added yet._\n`;
  }

  md += `\n## 📖 How to Use\n\n`;
  md += `1. Copy a script file to your Roblox executor\n`;
  md += `2. Load it in your Fluent GUI or execute directly\n`;
  md += `3. Scripts marked as "Paused" need to be enabled first\n\n`;

  md += `## 🔄 Update Scripts\n\n`;
  md += `When scripts are updated in chat:\n`;
  md += `1. Edit the `.scripts/` files locally\n`;
  md += `2. Commit and push changes\n`;
  md += `3. Update the game loader if needed\n\n`;

  md += `## 🏗️ Project Structure\n\n`;
  md += ````\n`;
  md += `${repoName}/\n`;
  md += `├── .scripts/          # Script definitions\n`;
  md += `│   └── scripts.json  # Registry\n`;
  md += `├── scripts/           # Actual script files\n`;
  md += `│   └── *.luau\n`;
  md += `└── README.md\n`;
  md += ````\n`;

  return md;
}

// Generate scripts.json registry
function generateScriptsJson(scripts) {
  return JSON.stringify(
    {
      version: "1.0.0",
      generated: new Date().toISOString(),
      scripts: scripts.map((s) => ({
        name: s.name || s.id || "unnamed",
        description: s.description || "No description",
        author: s.author || "Copilot",
        paused: !s.enabled,
        createdAt: s.createdAt || new Date().toISOString(),
      })),
    },
    null,
    2,
  );
}

// Main function
async function main() {
  console.log(`\n🚀 Generating Roblox Scripts Project`);
  console.log(`   Repository: ${owner}/${repoName}`);
  console.log(`   Output: ${outputPath}\n`);

  let scripts = [];

  if (listMode) {
    scripts = await readScriptsFromStdin();
    if (scripts.length === 0) {
      console.log("⚠️  No scripts received. Using empty project.\n");
    } else {
      console.log(`✅ Received ${scripts.length} script(s) from stdin\n`);
    }
  }

  // Ensure output directory
  fs.mkdirSync(outputPath, { recursive: true });

  // Create .scripts directory
  const scriptsDir = path.join(outputPath, ".scripts");
  fs.mkdirSync(scriptsDir, { recursive: true });

  // Write scripts.json
  const scriptsJsonPath = path.join(scriptsDir, "scripts.json");
  fs.writeFileSync(scriptsJsonPath, generateScriptsJson(scripts), "utf8");
  console.log(`📝 Written: ${path.relative(process.cwd(), scriptsJsonPath)}`);

  // Create scripts/ directory for actual files
  const scriptsCodeDir = path.join(outputPath, "scripts");
  if (scriptsCodeDir !== scriptsDir) {
    fs.mkdirSync(scriptsCodeDir, { recursive: true });
  }

  // If we have scripts, write them
  if (scripts.length > 0) {
    for (const script of scripts) {
      const scriptName = (script.name || script.id || "unnamed").replace(/[^a-zA-Z0-9_-]/g, "_");
      const scriptPath = path.join(scriptsCodeDir, `${scriptName}.luau`);

      let content = script.source || script.content || `-- Script: ${scriptName}\n-- Description: ${script.description || "No description"}\n-- Author: ${script.author || "Copilot"}\n-- Status: ${script.enabled ? "enabled" : "paused"}\n\n-- TODO: Add your script logic here\nprint("Script ${scriptName} loaded")\n`;

      // Add metadata header
      const header = `-- ⚠️ Auto-generated from Copilot Chat\n`;
      header += `-- Script: ${scriptName}\n`;
      header += `-- Description: ${script.description || "N/A"}\n`;
      header += `-- Author: ${script.author || "Copilot"}\n`;
      header += `-- Generated: ${new Date().toISOString()}\n`;
      header += `-- Paused: ${!script.enabled}\n`;
      header += `-- ═══════════════════════════════════════\n\n`;

      fs.writeFileSync(scriptPath, header + content, "utf8");
      console.log(`📄 Written: ${path.relative(process.cwd(), scriptPath)}`);
    }
  }

  // Write README
  const readmePath = path.join(outputPath, "README.md");
  fs.writeFileSync(
    readmePath,
    generateReadme({ owner, repoName, scriptsList: scripts }, scripts),
    "utf8",
  );
  console.log(`📖 Written: ${path.relative(process.cwd(), readmePath)}`);

  // Auto-commit if in a git repo
  try {
    const status = execSync("git status --porcelain", {
      encoding: "utf8",
      cwd: outputPath,
    }).trim();

    if (status) {
      console.log(`\n🔄 Committing changes...`);
      execSync(`git add -A "${outputPath}"`, {
        stdio: "inherit",
        cwd: process.cwd(),
      });
      execSync(`git commit -m "feat: add Roblox scripts for ${repoName}"`, {
        stdio: "inherit",
        cwd: process.cwd(),
      });
      console.log(`✅ Committed`);
    } else {
      console.log(`\n⏭️  No changes to commit`);
    }
  } catch (err) {
    console.log(`\n⚠️  Git commit skipped (not in a git repo or no changes)`);
  }

  // Push if requested
  if (shouldPush) {
    try {
      console.log(`\n📤 Pushing to GitHub...`);
      execSync("git push", { stdio: "inherit", cwd: process.cwd() });
      console.log(`✅ Pushed`);
    } catch (err) {
      console.log(`\n⚠️  Push failed: ${err.message}`);
    }
  }

  console.log(`\n✨ Done! Scripts project generated in: ${outputPath}`);
  return { owner, repoName, outputPath, scriptCount: scripts.length };
}

if (listMode) {
  main().catch((err) => {
    console.error("Error:", err.message);
    process.exit(1);
  });
} else {
  // For non-list mode, just create empty project structure
  main().catch((err) => {
    console.error("Error:", err.message);
    process.exit(1);
  });
}
