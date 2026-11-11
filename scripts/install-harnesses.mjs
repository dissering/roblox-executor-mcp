#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import fsSync from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import {
  DEFAULT_BRIDGE_URL,
  SERVER_PORT,
  buildLoaderSnippet,
  normalizeBridgeUrl,
} from "../src/shared/connector-snippet.mjs";
import {
  getDetectedAutoexecTargets,
  writeLoaderToAutoexec,
} from "../src/shared/autoexec.mjs";

const DEFAULT_SERVER_NAME = "roblox-mcp";
const MAIN_REPO_URL = "https://github.com/dissering/roblox-executor-mcp.git";
const SERVER_NAME = normalizeServerName(getArgValue("--server-name") || process.env.ROBLOX_MCP_SERVER_NAME || DEFAULT_SERVER_NAME);
const CURRENT_REPO_DIR = process.cwd();
const PACKAGE_VERSION = readPackageVersion();

const colors = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  cyan: "\x1b[36m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  purple: "\x1b[35m",
  gray: "\x1b[90m",
  inverse: "\x1b[7m",
};

const ALL_HARNESSES = [
  { id: "codex", name: "Codex", group: "Recommended", config: { kind: "codexToml", path: homePath(".codex", "config.toml") } },
  { id: "claude-code", name: "Claude Code", group: "Recommended", config: { kind: "claudeCli" } },
  { id: "opencode", name: "OpenCode", group: "Recommended", config: { kind: "opencodeJson", path: opencodeConfigPath() } },
  { id: "cursor", name: "Cursor", group: "Recommended", config: { kind: "mcpServersJson", path: homePath(".cursor", "mcp.json") } },
  { id: "trae", name: "Trae", group: "Recommended", config: { kind: "mcpServersJson", path: traeConfigPath() } },
  { id: "antigravity", name: "Antigravity", group: "Recommended", config: { kind: "mcpServersJson", path: antigravityConfigPath() } },
  { id: "gemini-cli", name: "Gemini CLI", group: "Recommended", config: { kind: "mcpServersJson", path: homePath(".gemini", "settings.json"), extra: { trust: true } } },
  { id: "github-copilot", name: "GitHub Copilot", group: "Recommended", config: { kind: "mcpServersJson", path: homePath(".copilot", "mcp-config.json") } },
  { id: "vscode-copilot", name: "VS Code Copilot", group: "Recommended", config: { kind: "vscodeCli" } },
  { id: "amp", name: "Amp", group: "Others", config: { kind: "ampJson", path: vscodeSettingsPath(), experimental: true } },
  { id: "blackbox", name: "BLACKBOX AI (VS Code)", group: "Others", config: { kind: "mcpServersJson", path: vscodeGlobalStoragePath("blackboxapp.blackboxagent", "settings", "blackbox_mcp_settings.json") } },
  { id: "cline", name: "Cline", group: "Others", config: { kind: "mcpServersJson", path: homePath(".cline", "data", "settings", "cline_mcp_settings.json") } },
  { id: "claude-desktop", name: "Claude Desktop", group: "Others", config: { kind: "mcpServersJson", paths: claudeDesktopConfigPaths() } },
  { id: "deep-agents", name: "Deep Agents", group: "Others", config: { kind: "mcpServersJson", path: homePath(".deepagents", ".mcp.json"), experimental: true } },
  { id: "kimi-cli", name: "Kimi CLI", group: "Others", config: { kind: "mcpServersJson", path: homePath(".kimi", "mcp.json"), experimental: true } },
  { id: "augment", name: "Augment", group: "Others", config: { kind: "mcpServersJson", path: homePath(".augment", "settings.json"), experimental: true } },
  { id: "continue", name: "Continue", group: "Others", config: { kind: "continueYaml", path: homePath(".continue", "config.yaml") } },
  { id: "devin-terminal", name: "Devin for Terminal", group: "Others", config: { kind: "mcpServersJson", path: homePath(".config", "devin", "config.json"), experimental: true } },
  { id: "goose", name: "Goose", group: "Others", config: { kind: "gooseYaml", path: gooseConfigPath(), experimental: true } },
  { id: "iflow-cli", name: "iFlow CLI", group: "Others", config: { kind: "mcpServersJson", path: homePath(".iflow", "settings.json"), experimental: true } },
  { id: "kilo-code", name: "Kilo Code", group: "Others", config: { kind: "kiloJson", path: homePath(".config", "kilo", "kilo.json"), experimental: true } },
  { id: "kiro-cli", name: "Kiro CLI", group: "Others", config: { kind: "mcpServersJson", path: homePath(".kiro", "settings", "mcp.json"), experimental: true } },
  { id: "mistral-vibe", name: "Mistral Vibe", group: "Others", config: { kind: "vibeToml", path: homePath(".vibe", "config.toml"), experimental: true } },
  { id: "openhands", name: "OpenHands", group: "Others", config: { kind: "mcpServersJson", path: homePath(".openhands", "mcp.json"), experimental: true } },
  { id: "qwen-code", name: "Qwen Code", group: "Others", config: { kind: "mcpServersJson", path: homePath(".qwen", "settings.json"), extra: { trust: true }, experimental: true } },
  { id: "rovo-dev", name: "Rovo Dev", group: "Others", config: { kind: "mcpServersJson", path: homePath(".rovodev", "mcp_config.json"), experimental: true } },
  { id: "roo-code", name: "Roo Code", group: "Others", config: { kind: "mcpServersJson", path: vscodeGlobalStoragePath("rooveterinaryinc.roo-cline", "settings", "mcp_settings.json"), experimental: true } },
  { id: "tabnine-cli", name: "Tabnine CLI", group: "Others", config: { kind: "mcpServersJson", path: homePath(".tabnine", "mcp_servers.json"), experimental: true } },
  { id: "windsurf", name: "Windsurf", group: "Others", config: { kind: "mcpServersJson", path: homePath(".codeium", "windsurf", "mcp_config.json") } },
  { id: "zcode", name: "ZCode", group: "Others", config: { kind: "zcodeJson", path: homePath(".zcode", "cli", "config.json") } },
  { id: "manual", name: "Manual", group: "Others", config: { kind: "manualRecipe" } },
];

const HARNESS_RESTART_SPECS = {
  antigravity: {
    key: "antigravity",
    label: "Antigravity",
    macApp: "Antigravity",
    commands: ["antigravity"],
    processNames: ["Antigravity"],
    windowsExecutables: ["Antigravity.exe"],
    windowsPaths: [
      path.join(process.env.LOCALAPPDATA || homePath("AppData", "Local"), "Programs", "Antigravity", "Antigravity.exe"),
    ],
  },
  cursor: {
    key: "cursor",
    label: "Cursor",
    macApp: "Cursor",
    commands: ["cursor"],
    processNames: ["Cursor"],
    windowsExecutables: ["Cursor.exe"],
    windowsPaths: [
      path.join(process.env.LOCALAPPDATA || homePath("AppData", "Local"), "Programs", "Cursor", "Cursor.exe"),
    ],
  },
  "claude-desktop": {
    key: "claude-desktop",
    label: "Claude Desktop",
    macApp: "Claude",
    processNames: ["Claude"],
    windowsExecutables: ["Claude.exe"],
    windowsPaths: [
      path.join(process.env.LOCALAPPDATA || homePath("AppData", "Local"), "Programs", "Claude", "Claude.exe"),
    ],
  },
  "vscode-copilot": {
    key: "vscode",
    label: "VS Code",
    macApp: "Visual Studio Code",
    commands: ["code"],
    processNames: ["Code", "Visual Studio Code"],
    windowsExecutables: ["Code.exe"],
    windowsPaths: [
      path.join(process.env.LOCALAPPDATA || homePath("AppData", "Local"), "Programs", "Microsoft VS Code", "Code.exe"),
      path.join(process.env.PROGRAMFILES || "C:\\Program Files", "Microsoft VS Code", "Code.exe"),
      path.join(process.env["PROGRAMFILES(X86)"] || "C:\\Program Files (x86)", "Microsoft VS Code", "Code.exe"),
    ],
  },
  windsurf: {
    key: "windsurf",
    label: "Windsurf",
    macApp: "Windsurf",
    commands: ["windsurf"],
    processNames: ["Windsurf"],
    windowsExecutables: ["Windsurf.exe"],
    windowsPaths: [
      path.join(process.env.LOCALAPPDATA || homePath("AppData", "Local"), "Programs", "Windsurf", "Windsurf.exe"),
    ],
  },
};

const EXPLICIT_HARNESS_IDS = parseHarnessIds(getArgValue("--harnesses"));
const LIST_HARNESSES_MODE = process.argv.includes("--list-harnesses-json");
const INSTALL_ONLY_MODE = process.argv.includes("--install-only");
const JSON_RESULT_MODE = process.argv.includes("--json-result");
const NON_INTERACTIVE = process.argv.includes("--yes") || process.argv.includes("-y") || EXPLICIT_HARNESS_IDS.length > 0;
const DRY_RUN = process.argv.includes("--dry-run");
const UPDATE_MODE = process.argv.includes("--update");
const GET_SCRIPT_MODE = process.argv.includes("--get-script");
const FORCE_ASCII_MODE = process.argv.includes("--ascii");
const LEGACY_WINDOWS_CONSOLE = process.platform === "win32" && !hasModernWindowsTerminal();
const ASCII_MODE = FORCE_ASCII_MODE || LEGACY_WINDOWS_CONSOLE || !terminalCanRenderUnicode();
const PLAIN_MODE = process.argv.includes("--plain");
const NO_OPENTUI = process.argv.includes("--no-opentui");
let OPEN_TUI_DISABLED = false;
const SHOW_ALL_HARNESSES = process.argv.includes("--show-all-harnesses") || process.argv.includes("--all-harnesses");
const AUTOEXEC_MODE = process.argv.includes("--autoexec");
installSafeTerminalWrites();
const HARNESS_AVAILABILITY = detectAvailableHarnesses();
if (PLAIN_MODE || process.env.NO_COLOR) {
  for (const key of Object.keys(colors)) {
    colors[key] = "";
  }
}

main().catch((error) => {
  console.error(`\n${colors.red}error:${colors.reset} ${error.message || error}`);
  process.exitCode = 1;
});

async function main() {
  if (LIST_HARNESSES_MODE) {
    console.log(JSON.stringify(ALL_HARNESSES.filter((harness) => harness.id !== "manual").map((harness) => {
      const availability = HARNESS_AVAILABILITY.get(harness.id) || { detected: false, reason: "" };
      return {
        id: harness.id,
        name: harness.name,
        group: harness.group,
        detected: availability.detected === true,
        reason: availability.reason || "",
      };
    })));
    return;
  }

  if (GET_SCRIPT_MODE) {
    await runGetScriptMode();
    return;
  }

  if (UPDATE_MODE) {
    await runUpdateMode();
    return;
  }

  const unknownHarnessIds = EXPLICIT_HARNESS_IDS.filter((id) => !ALL_HARNESSES.some((harness) => harness.id === id && id !== "manual"));
  if (unknownHarnessIds.length) {
    throw new Error(`Unknown harness${unknownHarnessIds.length === 1 ? "" : "es"}: ${unknownHarnessIds.join(", ")}`);
  }
  if (INSTALL_ONLY_MODE && !EXPLICIT_HARNESS_IDS.length) {
    throw new Error("--install-only requires at least one harness via --harnesses.");
  }

  const initial = new Set(EXPLICIT_HARNESS_IDS);
  const selected = NON_INTERACTIVE ? initial : await selectHarnesses(initial);
  if (!NON_INTERACTIVE) {
    console.log(`${colors.green}Selected harnesses:${colors.reset} ${formatSelection(selected)}`);
  }
  const crossMachine = NON_INTERACTIVE
    ? null
    : await configureCrossMachineSetup();
  const shouldPull =
    !NON_INTERACTIVE && canPullLatest(CURRENT_REPO_DIR)
      ? await askYesNo("Pull latest changes before install/build", false)
      : false;
  const semanticSettings = await readSemanticSettingsStatus();
  if (!NON_INTERACTIVE && semanticSettings.exists) {
    console.log(`${colors.cyan}Semantic indexing:${colors.reset} existing ${semanticSettings.summary}`);
  }
  const shouldOllama =
    NON_INTERACTIVE || semanticSettings.exists
      ? false
      : await askYesNo("Optionally set up Ollama + embeddinggemma for semantic indexing", false);

  const serverRoot = path.resolve(CURRENT_REPO_DIR);
  const serverEntry = path.join(serverRoot, "dist", "index.js");
  const results = [];

  section("Install");
  if (shouldPull) {
    await pullLatest(serverRoot, results);
  }
  if (INSTALL_ONLY_MODE) {
    if (!exists(serverEntry)) {
      throw new Error(`Server entry is missing at ${serverEntry}. Build the server before configuring a harness.`);
    }
    results.push({ status: "ok", message: `Using existing server entry at ${serverEntry}` });
  } else {
    await installServer(serverRoot, results);
  }

  if (crossMachine) {
    section("Network Setup");
    if (crossMachine.firewallStatus) {
      log(crossMachine.firewallStatus.status, crossMachine.firewallStatus.message);
    }
  }

  if (shouldOllama) {
    section("Ollama");
    await setupOllama(results);
  }

  section("Provider Configs");
  const selectedHarnesses = ALL_HARNESSES.filter((h) => selected.has(h.id));
  if (!selectedHarnesses.length) {
    log("skip", "No harnesses selected.");
  }
  for (const harness of selectedHarnesses) {
    await configureHarness(harness, serverEntry, results);
    if (INSTALL_ONLY_MODE && JSON_RESULT_MODE) {
      const result = results.findLast((item) => item.message.startsWith(`${harness.name}:`));
      console.log(`HARNESS_RESULT_JSON=${JSON.stringify({
        harness: {
          id: harness.id,
          name: harness.name,
          ok: result?.status === "ok",
          error: result?.status === "ok" ? null : result?.message.replace(`${harness.name}:`, "").trim() || "Configuration failed.",
        },
      })}`);
    }
  }
  await maybeRestartHarnesses(selectedHarnesses, results);

  section("Summary");
  for (const item of results) {
    log(item.status, item.message);
  }

  for (const harness of selectedHarnesses.filter((item) => item.config.kind === "manualRecipe")) {
    printManualMcpRecipe(harness, serverEntry);
  }

  const restartList = selectedHarnesses.length > 0
    ? selectedHarnesses.map((h) => h.name).join(", ")
    : "selected harnesses";
  const restartedHarnesses = results.some((item) => /: restarted$/.test(item.message));
  if (INSTALL_ONLY_MODE) {
    const harnessResults = selectedHarnesses.map((harness) => {
      const result = results.find((item) => item.message.startsWith(`${harness.name}:`));
      return {
        id: harness.id,
        name: harness.name,
        ok: result?.status === "ok",
        error: result?.status === "ok" ? null : result?.message.replace(`${harness.name}:`, "").trim() || "Configuration failed.",
      };
    });
    const failedHarnesses = harnessResults.filter((result) => !result.ok);
    if (JSON_RESULT_MODE) {
      console.log(`HARNESS_RESULT_JSON=${JSON.stringify({ harnesses: harnessResults })}`);
    }
    if (failedHarnesses.length) {
      process.exitCode = 1;
      console.log(`\n${colors.red}Install incomplete.${colors.reset} Review the harness errors above.`);
    } else {
      console.log(`\n${colors.green}Done.${colors.reset} Restart ${restartList} to load the MCP server.`);
    }
    showCursor();
    return;
  }

  const doneText = restartedHarnesses || selectedHarnesses.length === 0
    ? "Connect Roblox with:"
    : `Restart ${restartList}, then connect Roblox with:`;
  console.log(`\n${colors.green}Done.${colors.reset} ${doneText}`);
  const loaderSnippet = buildLoaderSnippet(crossMachine?.bridgeUrl);
  console.log(`${colors.cyan}${loaderSnippet}${colors.reset}`);
  if (crossMachine) {
    const copied = await copyToClipboard(loaderSnippet).catch((error) => {
      log("warn", `Could not copy Roblox loader to clipboard: ${error.message || error}`);
      return false;
    });
    if (copied) log("ok", "Roblox loader copied to clipboard");
  }
  if (!NON_INTERACTIVE || AUTOEXEC_MODE) {
    await maybeInstallAutoexec(loaderSnippet);
  }
  showCursor();
}

async function runGetScriptMode() {
  const bridgeArgIndex = process.argv.indexOf("--bridge-url");
  const bridgeUrl =
    bridgeArgIndex !== -1 && process.argv[bridgeArgIndex + 1]
      ? normalizeBridgeUrl(process.argv[bridgeArgIndex + 1])
      : await promptForGetScriptBridgeUrl();
  const loaderSnippet = buildLoaderSnippet(bridgeUrl);
  console.log(loaderSnippet);
  const copied = await copyToClipboard(loaderSnippet).catch((error) => {
    log("warn", `Could not copy Roblox loader to clipboard: ${error.message || error}`);
    return false;
  });
  if (copied) log("ok", "Roblox loader copied to clipboard");
  if (!NON_INTERACTIVE || AUTOEXEC_MODE) {
    await maybeInstallAutoexec(loaderSnippet);
  }
  showCursor();
}

async function maybeInstallAutoexec(loaderSnippet) {
  const targets = getDetectedAutoexecTargets();
  if (!targets.length) {
    log("warn", "No supported autoexec folder found. Known macOS and Windows executor paths are checked automatically.");
    return;
  }

  const targetText = targets.map((target) => shrinkHome(target.folder)).join(", ");
  const shouldInstall = AUTOEXEC_MODE || await askYesNo(`Install Roblox loader into autoexec (${targetText})`, false);
  if (!shouldInstall) return;

  const selectedTargets = AUTOEXEC_MODE ? targets : await selectAutoexecTargets(targets);
  if (!selectedTargets.length) return;

  const result = await writeLoaderToAutoexec(loaderSnippet, { targets: selectedTargets, dryRun: DRY_RUN });
  if (!result.ok) {
    log("warn", result.error || "Could not write autoexec script.");
    return;
  }
  for (const item of result.written) {
    const filePath = typeof item === "string" ? item : item.scriptPath;
    const previousPath = typeof item === "string" ? null : item.previousPath;
    const previousText = previousPath && previousPath !== filePath ? ` (existing connector detected at ${shrinkHome(previousPath)})` : "";
    log(DRY_RUN ? "dry" : "ok", `${DRY_RUN ? "Would write" : "Wrote"} autoexec loader to ${shrinkHome(filePath)}${previousText}`);
  }
}

async function selectAutoexecTargets(targets) {
  if (canUseRichPrompts()) {
    try {
      return await selectAutoexecTargetsOpenTui(targets);
    } catch (error) {
      log("warn", `OpenTUI autoexec picker unavailable: ${error.message || error}`);
      log("info", "Falling back to the plain numbered prompt.");
    }
  }

  if (targets.length <= 1) return targets;

  console.log(`${colors.cyan}Detected autoexec targets:${colors.reset}`);
  targets.forEach((target, index) => {
    const installed = target.installedPath ? ` ${colors.gray}(existing connector: ${shrinkHome(target.installedPath)})${colors.reset}` : "";
    console.log(`  ${String(index + 1).padStart(2)}. ${target.name} - ${shrinkHome(target.folder)}${installed}`);
  });

  const answer = await askInput("Autoexec target number(s), comma-separated, or 'all'", "all");
  const raw = answer.trim().toLowerCase();
  if (!raw || raw === "all") return targets;

  const selected = [];
  for (const part of raw.split(/[,\s]+/)) {
    const index = Number(part);
    if (!Number.isInteger(index) || index < 1 || index > targets.length) continue;
    const target = targets[index - 1];
    if (!selected.includes(target)) selected.push(target);
  }
  return selected;
}

async function selectAutoexecTargetsOpenTui(targets) {
  const { Box, Text, createCliRenderer } = await loadOpenTui();
  const ui = {
    bg: "#050505",
    left: "#0A0A0A",
    right: "#171717",
    topBox: "#101010",
    searchBox: "#1D1D1D",
    divider: "#222222",
    text: "#E7E7E7",
    muted: "#8E8E8E",
    dim: "#626262",
    blue: "#62A0FF",
    peach: "#F4B183",
    green: "#78D98C",
    amber: "#B9853D",
  };
  const state = {
    cursor: 0,
    search: "",
    mode: "list",
    selected: new Set(targets.map(autoexecTargetKey)),
  };

  return await new Promise((resolve, reject) => {
    let settled = false;
    let renderer;
    const cleanup = () => {
      if (settled) return;
      settled = true;
      if (renderer) renderer.destroy();
    };
    const finish = (selectedTargets) => {
      cleanup();
      resolve(selectedTargets);
    };
    const fail = createOpenTuiFailureHandler(cleanup, reject);
    const visibleItems = () => {
      const q = state.search.trim().toLowerCase();
      return targets.filter((target) => {
        const haystack = [
          target.name,
          target.id,
          target.folder,
          target.scriptPath,
          target.installedPath,
        ].filter(Boolean).join(" ").toLowerCase();
        return !q || haystack.includes(q);
      });
    };
    const render = guardOpenTuiHandler(() => {
      if (!renderer || settled) return;
      const items = visibleItems();
      if (state.cursor >= items.length) state.cursor = Math.max(0, items.length - 1);
      const activeItem = items[state.cursor] || null;
      const selectedCount = state.selected.size;
      const maxVisibleRows = getOpenTuiListHeight(renderer.height);
      const start = getWindowStart(items, state.cursor, maxVisibleRows);
      const windowed = items.slice(start, start + maxVisibleRows);
      const hiddenBelow = Math.max(0, items.length - (start + windowed.length));
      const scrollHint = start || hiddenBelow
        ? `${start ? `${start} above` : ""}${start && hiddenBelow ? " · " : ""}${hiddenBelow ? `${hiddenBelow} below` : ""}`
        : "ready";
      const searchText = state.mode === "search"
        ? `/ ${state.search}`
        : state.search
          ? `/ ${state.search}`
          : "/ to search executors";
      const searchHelpText = state.mode === "search"
        ? "type to filter   enter done   esc done"
        : "space toggle   a all   enter confirm   esc cancel";
      const viewportWidth = Math.max(60, Number(renderer.width || process.stdout.columns) || 120);
      const leftWidth = Math.max(38, Math.min(Math.floor(viewportWidth * 0.57), viewportWidth - 28));
      const dividerWidth = 1;
      const rightWidth = Math.max(26, viewportWidth - leftWidth - dividerWidth);

      const existingAutoexecRoot = renderer.root.getRenderable("autoexec-target-root");
      if (existingAutoexecRoot) existingAutoexecRoot.destroy();
      renderer.root.add(
        Box(
          {
            id: "autoexec-target-root",
            width: "100%",
            height: "100%",
            backgroundColor: ui.bg,
            flexDirection: "row",
          },
          Box(
            {
              width: leftWidth,
              height: "100%",
              paddingX: 3,
              paddingY: 2,
              flexDirection: "column",
              overflow: "hidden",
              backgroundColor: ui.left,
            },
            Box(
              {
                width: "100%",
                height: 4,
                flexDirection: "row",
                backgroundColor: ui.topBox,
              },
              Box({ width: 1, height: "100%", backgroundColor: ui.blue }),
              Box(
                {
                  flexGrow: 1,
                  height: "100%",
                  paddingX: 2,
                  paddingY: 1,
                  flexDirection: "column",
                },
                Text({
                  content: "Autoexec Loader",
                  fg: ui.text,
                  attributes: 1,
                  height: 1,
                  truncate: true,
                }),
                Text({
                  content: "Choose executor autoexec folders",
                  fg: ui.muted,
                  height: 1,
                  truncate: true,
                })
              )
            ),
            Box(
              {
                width: "100%",
                flexGrow: 1,
                paddingX: 3,
                paddingY: 3,
                flexDirection: "column",
                backgroundColor: ui.left,
              },
              Text({ content: "Detected Executors", fg: ui.muted, attributes: 1, height: 1, truncate: true }),
              ...autoexecTargetListNodes(Box, Text, windowed, activeItem, state.selected, ui),
              Box({ flexGrow: 1 }),
              Text({
                content: selectedCount ? `${selectedCount} target${selectedCount === 1 ? "" : "s"} selected` : "No targets selected",
                fg: selectedCount ? ui.text : ui.amber,
                attributes: 1,
                height: 1,
                truncate: true,
              }),
              Text({
                content: selectedCount ? "Only selected executors will get the loader" : "Press space to select an executor",
                fg: ui.dim,
                height: 1,
                truncate: true,
              })
            ),
            Box(
              {
                width: "100%",
                height: 4,
                flexDirection: "row",
                backgroundColor: ui.searchBox,
              },
              Box({ width: 1, height: "100%", backgroundColor: ui.blue }),
              Box(
                {
                  flexGrow: 1,
                  height: "100%",
                  paddingX: 2,
                  paddingY: 1,
                  flexDirection: "column",
                },
                Text({
                  content: searchText,
                  fg: state.mode === "search" ? ui.peach : ui.text,
                  attributes: state.mode === "search" ? 1 : 0,
                  height: 1,
                  truncate: true,
                }),
                Text({
                  content: searchHelpText,
                  fg: ui.dim,
                  height: 1,
                  truncate: true,
                })
              )
            )
          ),
          Box({ width: dividerWidth, height: "100%", backgroundColor: ui.divider }),
          Box(
            {
              width: rightWidth,
              height: "100%",
              overflow: "hidden",
              backgroundColor: ui.right,
              paddingX: 3,
              paddingY: 2,
              flexDirection: "column",
            },
            Text({ content: "Autoexec Installation", fg: ui.text, attributes: 1, height: 1, truncate: true }),
            Box({ height: 2 }),
            Text({ content: "Executors", fg: ui.text, attributes: 1, height: 1, truncate: true }),
            Text({ content: `${targets.length} detected`, fg: ui.text, height: 1, truncate: true }),
            Text({ content: `${selectedCount} selected`, fg: selectedCount ? ui.text : ui.muted, height: 1, truncate: true }),
            Box({ height: 2 }),
            Text({ content: "Target Info", fg: ui.text, attributes: 1, height: 1, truncate: true }),
            ...autoexecTargetInfoNodes(Box, Text, activeItem, ui),
            Box({ flexGrow: 1 }),
            Text({ content: `Roblox Executor MCP v${PACKAGE_VERSION}`, fg: ui.text, attributes: 1, height: 1, truncate: true }),
            Text({ content: `${scrollHint} · autoexec loader`, fg: ui.dim, height: 1, truncate: true })
          )
        )
      );
      renderer.requestRender();
    }, fail);
    const onKey = guardOpenTuiHandler((key) => {
      if (settled) return;
      const items = visibleItems();
      if (key.name === "c" && key.ctrl) {
        cleanup();
        process.exit(130);
      }
      if (state.mode === "search") {
        if (key.name === "return" || key.name === "escape") state.mode = "list";
        else if (key.name === "backspace") state.search = state.search.slice(0, -1);
        else if (key.sequence && key.sequence.length === 1 && !key.ctrl && !key.meta) state.search += key.sequence;
        state.cursor = 0;
        render();
        return;
      }
      if (key.name === "down") state.cursor = Math.min(items.length - 1, state.cursor + 1);
      else if (key.name === "up") state.cursor = Math.max(0, state.cursor - 1);
      else if (key.name === "pagedown") state.cursor = Math.min(items.length - 1, state.cursor + getOpenTuiListHeight(renderer.height));
      else if (key.name === "pageup") state.cursor = Math.max(0, state.cursor - getOpenTuiListHeight(renderer.height));
      else if (key.name === "home") state.cursor = 0;
      else if (key.name === "end") state.cursor = Math.max(0, items.length - 1);
      else if (key.name === "space" && items[state.cursor]) toggle(state.selected, autoexecTargetKey(items[state.cursor]));
      else if (key.name === "a") {
        const allVisibleSelected = items.length > 0 && items.every((item) => state.selected.has(autoexecTargetKey(item)));
        for (const item of items) {
          allVisibleSelected ? state.selected.delete(autoexecTargetKey(item)) : state.selected.add(autoexecTargetKey(item));
        }
      } else if (key.name === "slash" || key.sequence === "/") state.mode = "search";
      else if (key.name === "backspace") state.search = state.search.slice(0, -1);
      else if (key.name === "q" || key.name === "escape") {
        finish([]);
        return;
      } else if (key.name === "return") {
        finish(targets.filter((target) => state.selected.has(autoexecTargetKey(target))));
        return;
      }
      render();
    }, fail);

    createCliRenderer(openTuiRendererConfig(ui.bg)).then((created) => {
      if (settled) {
        created.destroy();
        return;
      }
      renderer = created;
      renderer.keyInput.on("keypress", onKey);
      renderer.on("resize", render);
      hideCursor();
      render();
    }).catch(fail);
  });
}

function autoexecTargetListNodes(Box, Text, items, activeItem, selected, palette) {
  const nodes = [];
  for (const target of items) {
    const active = target === activeItem;
    const checked = selected.has(autoexecTargetKey(target));
    const rowBg = active ? palette.peach : palette.left;
    nodes.push(Box(
      {
        width: "100%",
        height: 1,
        flexDirection: "row",
        backgroundColor: rowBg,
      },
      Text({
        content: `  ${target.name}`,
        fg: active ? palette.bg : checked ? palette.text : palette.muted,
        bg: rowBg,
        attributes: active || checked ? 1 : 0,
        height: 1,
        truncate: true,
      }),
      Box({ flexGrow: 1, height: 1, backgroundColor: rowBg }),
      Text({
        content: checked ? "✓ " : "  ",
        fg: active ? "#0F5132" : palette.green,
        bg: rowBg,
        height: 1,
        truncate: true,
      })
    ));
  }
  if (!nodes.length) {
    nodes.push(Text({
      content: "No executors match that search.",
      fg: palette.amber,
      height: 1,
      truncate: true,
      width: "100%",
    }));
  }
  return nodes;
}

function autoexecTargetInfoNodes(Box, Text, target, palette) {
  if (!target) {
    return [
      Text({ content: "No matches", fg: palette.dim, attributes: 1, height: 1, truncate: true }),
      Text({ content: "Clear the search to show detected executors again.", fg: palette.muted, wrapMode: "word", height: 2 }),
    ];
  }

  const detectionLines = autoexecDetectionInfoLines(target);
  return [
    infoDotRow(Box, Text, palette, palette.green, `Name: ${target.name}`, palette.text),
    infoDotRow(Box, Text, palette, palette.green, "Detected", palette.text),
    Box({ height: 1 }),
    Text({ content: "Detection Info", fg: palette.text, attributes: 1, height: 1, truncate: true }),
    ...detectionLines.map((line) => Text({
      content: `- ${line}`,
      fg: palette.muted,
      height: 1,
      truncate: true,
    })),
  ];
}

function autoexecDetectionInfoLines(target) {
  const lines = [
    shrinkHome(target.folder),
    `writes ${path.basename(target.scriptPath)}`,
  ];
  if (target.installedPath) lines.push(`existing connector ${shrinkHome(target.installedPath)}`);
  return lines;
}

function autoexecTargetKey(target) {
  return target?.folder || target?.id || "";
}

async function promptForGetScriptBridgeUrl() {
  if (NON_INTERACTIVE) return DEFAULT_BRIDGE_URL;

  const target = await promptForBridgeTarget("Roblox connection for loader");
  return target.bridgeUrl;
}

async function runUpdateMode() {
  const serverRoot = path.resolve(CURRENT_REPO_DIR);
  const results = [];

  section("Update");
  log("info", `Using current repository: ${serverRoot}`);
  await ensureUpdateGitReady(serverRoot, results);

  const processes = findMcpServerProcesses(serverRoot);
  if (processes.length) {
    console.log(`${colors.yellow}Found ${processes.length} running MCP server process(es):${colors.reset}`);
    for (const proc of processes) {
      console.log(`${colors.gray}${String(proc.pid).padStart(6)}${colors.reset} ${proc.command}`);
    }
    const shouldKill =
      !NON_INTERACTIVE && (await askYesNo("Kill running MCP server processes before updating", false));
    if (shouldKill) {
      killProcesses(processes, results);
    } else {
      results.push({
        status: "warn",
        message: "Running MCP server processes were left alive. Restart clients after updating so they use the new build.",
      });
    }
  } else {
    log("skip", "No running MCP server processes found.");
  }

  const shouldPull =
    !NON_INTERACTIVE && canPullLatest(serverRoot)
      ? await askYesNo("Pull latest changes before rebuild", false)
      : false;
  if (shouldPull) {
    await pullLatest(serverRoot, results);
  }

  await installServer(serverRoot, results, { announceRepo: false });

  section("Summary");
  for (const item of results) {
    log(item.status, item.message);
  }
  showCursor();
}

async function installServer(serverRoot, results, options = {}) {
  if (options.announceRepo !== false) {
    log("info", `Using current repository: ${serverRoot}`);
  }
  const runner = commandExists("bun") ? "bun" : commandExists("pnpm") ? "pnpm" : "npm";
  await run(
    runner,
    ["install", "--ignore-scripts"],
    { cwd: serverRoot, label: `Installing dependencies with ${runner}` }
  );
  await run(runner, ["run", "build"], { cwd: serverRoot, label: "Building server" });
  const serverEntry = path.join(serverRoot, "dist", "index.js");
  if (!exists(serverEntry)) {
    if (DRY_RUN) {
      results.push({ status: "dry", message: `Would prepare server at ${serverRoot}` });
      results.push({ status: "dry", message: `Would verify server entry at ${serverEntry}` });
      return;
    }
    throw new Error(`Build completed, but ${serverEntry} was not created.`);
  }
  results.push({ status: DRY_RUN ? "dry" : "ok", message: `${DRY_RUN ? "Would prepare" : "Server ready at"} ${serverRoot}` });
  results.push({ status: DRY_RUN ? "dry" : "ok", message: `${DRY_RUN ? "Would verify" : "Server entry verified at"} ${serverEntry}` });
}

async function pullLatest(serverRoot, results) {
  await run("git", ["pull", "--ff-only"], { cwd: serverRoot, label: "Pulling latest changes" });
  results.push({ status: "ok", message: "Repository updated with latest changes" });
}

async function ensureUpdateGitReady(serverRoot, results) {
  if (!commandExists("git")) {
    const installed = await maybeInstallGit(results);
    if (!installed) return false;
  }

  if (!isGitRepository(serverRoot)) {
    results.push({
      status: "warn",
      message: "Current folder is not a git repository. Update can rebuild, but it cannot pull latest changes.",
    });
    return false;
  }

  const originUrl = getGitOriginUrl(serverRoot);
  if (!originUrl) {
    const shouldSetOrigin =
      NON_INTERACTIVE || await askYesNo(`Set git origin to ${MAIN_REPO_URL}`, true);
    if (shouldSetOrigin) {
      await setGitOrigin(serverRoot, false, results);
      return true;
    }
    results.push({ status: "warn", message: "Git origin is not set; skipping remote update setup." });
    return false;
  }

  if (!isMainRepoRemote(originUrl)) {
    const shouldSetOrigin =
      NON_INTERACTIVE || await askYesNo(`Origin is ${originUrl}. Set it to the main repo`, false);
    if (shouldSetOrigin) {
      await setGitOrigin(serverRoot, true, results);
      return true;
    }
    results.push({ status: "warn", message: `Git origin left unchanged: ${originUrl}` });
    return false;
  }

  log("ok", `Git origin: ${originUrl}`);
  return true;
}

async function maybeInstallGit(results) {
  if (process.platform === "win32" && !commandExists("winget")) {
    const installedWinget = await maybeInstallWinget(results);
    if (!installedWinget) {
      results.push({
        status: "warn",
        message: "Git is not installed and winget is unavailable, so automatic Git installation cannot continue.",
      });
      return false;
    }
  }

  const plan = getGitInstallPlan();
  if (!plan) {
    results.push({
      status: "warn",
      message: "Git is not installed and no supported automatic installer was found.",
    });
    return false;
  }

  const shouldInstall =
    NON_INTERACTIVE || await askYesNo(`Git is not installed. Install Git using ${plan.label}`, true);
  if (!shouldInstall) {
    results.push({ status: "warn", message: "Git is not installed; skipping pull/update remote checks." });
    return false;
  }

  await runForeground(plan.command, plan.args, {
    label: `Installing Git with ${plan.label}`,
    cwd: CURRENT_REPO_DIR,
  });

  if (!commandExists("git")) {
    results.push({
      status: "warn",
      message: "Git installer finished, but git is still not available in PATH. Restart the terminal and run update again.",
    });
    return false;
  }

  results.push({ status: "ok", message: "Git is installed." });
  return true;
}

async function maybeInstallWinget(results) {
  const shouldInstall =
    NON_INTERACTIVE || await askYesNo("winget is not installed. Install Windows Package Manager now", true);
  if (!shouldInstall) {
    results.push({ status: "warn", message: "winget is not installed; skipping automatic Git installation." });
    return false;
  }

  const plan = getWingetInstallPlan();
  await runForeground(plan.command, plan.args, {
    label: `Installing ${plan.label}`,
    cwd: CURRENT_REPO_DIR,
  });

  if (!commandExists("winget")) {
    results.push({
      status: "warn",
      message: "Windows Package Manager installer finished, but winget is still not available in PATH. Restart the terminal and run update again.",
    });
    return false;
  }

  results.push({ status: "ok", message: "Windows Package Manager is installed." });
  return true;
}

function getWingetInstallPlan() {
  const script = [
    "$ErrorActionPreference = 'Stop'",
    "try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe } catch { Write-Host \"App Installer registration skipped: $($_.Exception.Message)\" }",
    "if (Get-Command winget -ErrorAction SilentlyContinue) { exit 0 }",
    "$bundle = Join-Path $env:TEMP 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'",
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12",
    "Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $bundle -UseBasicParsing",
    "Add-AppxPackage -Path $bundle",
    "if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget was installed, but winget.exe is not available in PATH yet.' }",
  ].join("; ");
  return {
    label: "Windows Package Manager",
    command: "powershell.exe",
    args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
  };
}

function getGitInstallPlan() {
  if (process.platform === "darwin") {
    if (commandExists("brew")) {
      return { label: "Homebrew", command: "brew", args: ["install", "git"] };
    }
    if (exists("/usr/bin/xcode-select")) {
      return { label: "Xcode Command Line Tools", command: "xcode-select", args: ["--install"] };
    }
    return null;
  }

  if (process.platform === "win32") {
    if (commandExists("winget")) {
      return {
        label: "winget",
        command: "winget",
        args: ["install", "--id", "Git.Git", "-e", "--source", "winget"],
      };
    }
    return null;
  }

  const isRoot = process.getuid && process.getuid() === 0;
  const sudo = !isRoot && commandExists("sudo") ? "sudo" : null;
  if (!isRoot && !sudo) return null;
  const rootPrefix = sudo ? [sudo] : [];
  if (commandExists("apt-get")) {
    return {
      label: "apt",
      command: rootPrefix[0] || "sh",
      args: rootPrefix[0]
        ? ["sh", "-c", "apt-get update && apt-get install -y git"]
        : ["-c", "apt-get update && apt-get install -y git"],
    };
  }
  if (commandExists("dnf")) {
    return {
      label: "dnf",
      command: rootPrefix[0] || "dnf",
      args: rootPrefix[0] ? ["dnf", "install", "-y", "git"] : ["install", "-y", "git"],
    };
  }
  if (commandExists("yum")) {
    return {
      label: "yum",
      command: rootPrefix[0] || "yum",
      args: rootPrefix[0] ? ["yum", "install", "-y", "git"] : ["install", "-y", "git"],
    };
  }
  if (commandExists("pacman")) {
    return {
      label: "pacman",
      command: rootPrefix[0] || "pacman",
      args: rootPrefix[0] ? ["pacman", "-S", "--needed", "--noconfirm", "git"] : ["-S", "--needed", "--noconfirm", "git"],
    };
  }
  return null;
}

function getGitOriginUrl(serverRoot) {
  const result = spawnSync("git", ["remote", "get-url", "origin"], {
    cwd: serverRoot,
    encoding: "utf8",
    windowsHide: true,
  });
  if (result.status !== 0) return null;
  return result.stdout.trim() || null;
}

function canPullLatest(serverRoot) {
  return commandExists("git") && isGitRepository(serverRoot) && Boolean(getGitOriginUrl(serverRoot));
}

function isMainRepoRemote(value) {
  return normalizeGitRemote(value) === normalizeGitRemote(MAIN_REPO_URL);
}

function normalizeGitRemote(value) {
  let remote = String(value || "").trim();
  remote = remote.replace(/^git@github\.com:/i, "https://github.com/");
  remote = remote.replace(/^ssh:\/\/git@github\.com\//i, "https://github.com/");
  remote = remote.replace(/^http:\/\//i, "https://");
  remote = remote.replace(/\/+$/, "");
  remote = remote.replace(/\.git$/i, "");
  return remote.toLowerCase();
}

async function setGitOrigin(serverRoot, replaceExisting, results) {
  const action = replaceExisting ? "set-url" : "add";
  await run("git", ["remote", action, "origin", MAIN_REPO_URL], {
    cwd: serverRoot,
    label: `${replaceExisting ? "Updating" : "Setting"} git origin`,
  });
  results.push({
    status: DRY_RUN ? "dry" : "ok",
    message: `${DRY_RUN ? "Would set git origin" : "Git origin set"} to ${MAIN_REPO_URL}`,
  });
}

function findMcpServerProcesses(serverRoot) {
  const serverEntry = path.join(serverRoot, "dist", "index.js");
  const normalizedEntry = normalizeProcessPath(serverEntry);
  const normalizedRoot = normalizeProcessPath(serverRoot);

  if (process.platform === "win32") {
    const script = [
      "$ErrorActionPreference = 'SilentlyContinue';",
      "Get-CimInstance Win32_Process |",
      "Where-Object { $_.CommandLine -and ($_.CommandLine -like '*dist/index.js*' -or $_.CommandLine -like '*dist\\\\index.js*') } |",
      "ForEach-Object { [PSCustomObject]@{ ProcessId = $_.ProcessId; CommandLine = $_.CommandLine } } |",
      "ConvertTo-Json -Compress",
    ].join(" ");
    const result = spawnSync("powershell.exe", ["-NoProfile", "-Command", script], {
      encoding: "utf8",
      windowsHide: true,
    });
    if (result.status !== 0 || !result.stdout.trim()) return [];
    try {
      const parsed = JSON.parse(result.stdout);
      const rows = Array.isArray(parsed) ? parsed : [parsed];
      return rows
        .map((row) => ({ pid: Number(row.ProcessId), command: String(row.CommandLine || "") }))
        .filter((row) => isMatchingMcpProcess(row, normalizedEntry, normalizedRoot));
    } catch {
      return [];
    }
  }

  const result = spawnSync("ps", ["-axo", "pid=,command="], { encoding: "utf8" });
  if (result.status !== 0) return [];
  return result.stdout
    .split(/\r?\n/)
    .map((line) => {
      const match = line.trim().match(/^(\d+)\s+(.+)$/);
      return match ? { pid: Number(match[1]), command: match[2] } : null;
    })
    .filter(Boolean)
    .filter((row) => isMatchingMcpProcess(row, normalizedEntry, normalizedRoot));
}

function isMatchingMcpProcess(proc, normalizedEntry, normalizedRoot) {
  if (!proc || !Number.isInteger(proc.pid) || proc.pid === process.pid) return false;
  const command = normalizeProcessPath(proc.command);
  return (
    command.includes(normalizedEntry) ||
    (command.includes("dist/index.js") && command.includes(normalizedRoot))
  );
}

function normalizeProcessPath(value) {
  return String(value || "").replace(/\\/g, "/");
}

function killProcesses(processes, results) {
  if (DRY_RUN) {
    log("dry", `Would kill ${processes.length} MCP server process(es)`);
    return;
  }

  for (const proc of processes) {
    try {
      process.kill(proc.pid, "SIGTERM");
      results.push({ status: "ok", message: `Killed MCP server process ${proc.pid}` });
    } catch (error) {
      results.push({
        status: "warn",
        message: `Could not kill MCP server process ${proc.pid}: ${error.message || error}`,
      });
    }
  }
}

async function setupOllama(results) {
  if (!commandExists("ollama")) {
    const installed = await tryInstallOllama();
    if (!installed) {
      results.push({
        status: "warn",
        message: "Ollama was not found and no supported package manager was available. Install Ollama, then run `ollama pull embeddinggemma`.",
      });
      return;
    }
  }

  await run("ollama", ["pull", "embeddinggemma"], { label: "Pulling embeddinggemma" });
  const settingsPath = homePath(".roblox-mcp", "semantic-search.json");
  await writeJson(settingsPath, {
    provider: "ollama",
    openaiApiKey: "",
    openaiBaseUrl: "https://api.openai.com/v1",
    openaiModel: "text-embedding-3-small",
    ollamaBaseUrl: "http://localhost:11434",
    ollamaModel: "embeddinggemma",
    saveEmbeddingsToDisk: true,
  });
  results.push({ status: "ok", message: `Semantic settings wrote Ollama + embeddinggemma to ${settingsPath}` });
}

async function configureCrossMachineSetup() {
  const target = await promptForBridgeTarget("How should Roblox reach this MCP server");
  if (target.mode === "current") return null;

  let firewallStatus = null;
  const firewallPlan = target.needsFirewall ? getFirewallPlan() : null;
  if (firewallPlan) {
    const shouldPatchFirewall = await askYesNo(
      `Allow inbound TCP ${SERVER_PORT} through the firewall`,
      false
    );
    if (shouldPatchFirewall) {
      try {
        await run(firewallPlan.command, firewallPlan.args, { label: firewallPlan.label });
        firewallStatus = { status: "ok", message: firewallPlan.success };
      } catch (error) {
        firewallStatus = { status: "warn", message: `Firewall setup failed: ${error.message || error}` };
      }
    } else {
      firewallStatus = {
        status: "warn",
        message: `Firewall not changed. Make sure inbound TCP ${SERVER_PORT} is allowed for cross-machine Roblox clients.`,
      };
    }
  } else {
    firewallStatus = {
      status: "warn",
      message: `No automatic firewall patch is available for this OS. Allow inbound TCP ${SERVER_PORT} manually if clients cannot connect.`,
    };
  }

  return { bridgeUrl: target.bridgeUrl, firewallStatus };
}

async function promptForBridgeTarget(label) {
  const lanIp = getLocalLanIp();
  const tailscaleIp = getTailscaleIp();
  const options = [
    {
      key: "1",
      aliases: ["current", "this", "computer", "localhost"],
      mode: "current",
      title: "This computer",
      bridgeUrl: DEFAULT_BRIDGE_URL,
      needsFirewall: false,
      detail: DEFAULT_BRIDGE_URL,
    },
    {
      key: "2",
      aliases: ["local", "network", "lan", "wifi", "local-network"],
      mode: "network",
      title: "Local network",
      bridgeUrl: normalizeBridgeUrl(lanIp || "127.0.0.1"),
      needsFirewall: true,
      detail: lanIp ? normalizeBridgeUrl(lanIp) : "manual address",
    },
    {
      key: "3",
      aliases: ["tailscale", "tailnet", "authorized", "authorized-machines"],
      mode: "tailscale",
      title: "Tailscale",
      bridgeUrl: tailscaleIp ? normalizeBridgeUrl(tailscaleIp) : "",
      needsFirewall: false,
      detail: tailscaleIp ? normalizeBridgeUrl(tailscaleIp) : "manual address",
    },
  ];

  const answer = await askChoice(label, options, "1");
  const choice = findBridgeTargetOption(options, answer);
  if (choice.mode === "current") return choice;

  const fallback = choice.bridgeUrl || (choice.mode === "tailscale" ? "" : DEFAULT_BRIDGE_URL);
  const address = await askInput(`${choice.title} bridge address`, fallback);
  if (choice.mode === "tailscale" && !String(address || "").trim()) {
    log("warn", "No Tailscale address entered. Falling back to this computer.");
    return options[0];
  }
  return {
    ...choice,
    bridgeUrl: normalizeBridgeUrl(address || fallback),
  };
}

function findBridgeTargetOption(options, value) {
  const raw = String(value || "").trim().toLowerCase();
  return options.find((option) => {
    return option.key === raw || option.aliases.includes(raw) || option.mode === raw;
  }) || options[0];
}

function getLocalLanIp() {
  const nets = os.networkInterfaces();
  const candidates = [];
  for (const entries of Object.values(nets)) {
    for (const entry of entries || []) {
      if (entry.family !== "IPv4" || entry.internal) continue;
      candidates.push(entry.address);
    }
  }
  return candidates.find((ip) => /^10\./.test(ip) || /^192\.168\./.test(ip) || /^172\.(1[6-9]|2\d|3[0-1])\./.test(ip)) || candidates[0] || null;
}

function getTailscaleIp() {
  const binary = findTailscaleBinary();
  if (!binary) return null;
  const result = spawnSync(binary, ["ip", "-4"], {
    encoding: "utf8",
    stdio: "pipe",
    shell: false,
  });
  if (result.status !== 0) return null;
  const ip = result.stdout.split(/\r?\n/).map((line) => line.trim()).find(Boolean);
  return ip || null;
}

function findTailscaleBinary() {
  const command = process.platform === "win32" ? "tailscale.exe" : "tailscale";
  const fromPath = findOnPath(command);
  if (fromPath) return fromPath;
  const candidates = process.platform === "darwin"
    ? [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
      ]
    : process.platform === "win32"
      ? [
          "C:\\Program Files\\Tailscale\\tailscale.exe",
          "C:\\Program Files (x86)\\Tailscale\\tailscale.exe",
        ]
      : ["/usr/bin/tailscale", "/usr/local/bin/tailscale"];
  return candidates.find((filePath) => exists(filePath)) || null;
}

async function copyToClipboard(text) {
  const command =
    process.platform === "darwin"
      ? "pbcopy"
      : process.platform === "win32"
        ? "clip"
        : commandExists("wl-copy")
          ? "wl-copy"
          : commandExists("xclip")
            ? "xclip"
            : null;

  if (!command) {
    log("warn", "Clipboard tool not found; copy the loader from the final output.");
    return;
  }

  if (DRY_RUN) {
    log("dry", `Would copy Roblox loader to clipboard with ${command}`);
    return false;
  }

  await new Promise((resolve, reject) => {
    const args = command === "xclip" ? ["-selection", "clipboard"] : [];
    const child = spawn(command, args, { stdio: ["pipe", "ignore", "pipe"], shell: false });
    let errorOutput = "";
    child.stderr.on("data", (chunk) => {
      errorOutput += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(errorOutput.trim() || `${command} exited with code ${code}`));
    });
    child.stdin.end(text);
  });
  return true;
}

function getFirewallPlan() {
  if (process.platform === "win32") {
    return {
      command: "netsh",
      args: [
        "advfirewall",
        "firewall",
        "add",
        "rule",
        `name=Roblox Executor MCP ${SERVER_PORT}`,
        "dir=in",
        "action=allow",
        "protocol=TCP",
        `localport=${SERVER_PORT}`,
      ],
      label: `Adding Windows firewall rule for TCP ${SERVER_PORT}`,
      success: `Windows firewall allows inbound TCP ${SERVER_PORT}.`,
    };
  }

  if (commandExists("ufw")) {
    return {
      command: "sudo",
      args: ["-n", "ufw", "allow", `${SERVER_PORT}/tcp`],
      label: `Allowing TCP ${SERVER_PORT} with ufw`,
      success: `ufw allows inbound TCP ${SERVER_PORT}.`,
    };
  }

  if (commandExists("firewall-cmd")) {
    return {
      command: "sudo",
      args: ["-n", "firewall-cmd", "--add-port", `${SERVER_PORT}/tcp`, "--permanent"],
      label: `Allowing TCP ${SERVER_PORT} with firewalld`,
      success: `firewalld allows inbound TCP ${SERVER_PORT}; reload firewalld if needed.`,
    };
  }

  return null;
}

async function readSemanticSettingsStatus() {
  const filePath = homePath(".roblox-mcp", "semantic-search.json");
  if (!exists(filePath)) return { exists: false, summary: "" };
  try {
    const settings = await readJson(filePath, {});
    const provider = typeof settings.provider === "string" && settings.provider ? settings.provider : "configured";
    const model =
      provider === "ollama"
        ? settings.ollamaModel
        : provider === "openai"
          ? settings.openaiModel
          : settings.ollamaModel || settings.openaiModel;
    return {
      exists: true,
      summary: `${provider}${typeof model === "string" && model ? ` / ${model}` : ""} at ${filePath}`,
    };
  } catch {
    return { exists: false, summary: "" };
  }
}

async function tryInstallOllama() {
  if (process.platform === "darwin" && commandExists("brew")) {
    await run("brew", ["install", "ollama"], { label: "Installing Ollama with Homebrew" });
    return true;
  }
  if (process.platform === "win32" && commandExists("winget")) {
    await run("winget", ["install", "--id", "Ollama.Ollama", "-e"], { label: "Installing Ollama with winget" });
    return true;
  }
  if (process.platform === "linux" && commandExists("apt-get")) {
    log("warn", "Automatic apt installation is intentionally skipped because Ollama's official installer varies by distro.");
  }
  return false;
}

async function configureHarness(harness, serverEntry, results) {
  try {
    switch (harness.config.kind) {
      case "mcpServersJson":
        for (const filePath of configPaths(harness.config)) {
          await writeMcpServersJson(filePath, serverEntry, harness.config.extra);
        }
        break;
      case "opencodeJson":
        await writeOpencodeJson(harness.config.path, serverEntry);
        break;
      case "kiloJson":
        await writeKiloJson(harness.config.path, serverEntry);
        break;
      case "ampJson":
        await writeAmpJson(harness.config.path, serverEntry);
        break;
      case "codexToml":
        await writeCodexToml(harness.config.path, serverEntry);
        break;
      case "continueYaml":
        await writeContinueYaml(harness.config.path, serverEntry);
        break;
      case "gooseYaml":
        await writeGooseYaml(harness.config.path, serverEntry);
        break;
      case "vibeToml":
        await writeVibeToml(harness.config.path, serverEntry);
        break;
      case "claudeCli":
        await configureClaudeCode(serverEntry);
        break;
      case "vscodeCli":
        await configureVsCodeCopilot(serverEntry);
        break;
      case "zcodeJson":
        await writeZcodeJson(harness.config.path, serverEntry);
        break;
      case "manualRecipe":
        results.push({ status: "warn", message: `${harness.name}: printed manual MCP recipe.` });
        return;
      default:
        throw new Error(`Unknown config writer: ${harness.config.kind}`);
    }
    const suffix = harness.config.experimental ? " (experimental path)" : "";
    const configuredPaths = configPaths(harness.config);
    const configuredPathText = configuredPaths.length ? ` ${configuredPaths.join(", ")}` : "";
    results.push({ status: "ok", message: `${harness.name}: configured${configuredPathText}${suffix}` });
  } catch (error) {
    results.push({ status: "warn", message: `${harness.name}: ${error.message || error}` });
  }
}

async function maybeRestartHarnesses(selectedHarnesses, results) {
  if (INSTALL_ONLY_MODE || NON_INTERACTIVE || !selectedHarnesses.length) return;

  const restartable = findRestartableHarnesses(selectedHarnesses);
  if (!restartable.length) return;

  section("Restart Harnesses");
  const names = restartable.map((target) => target.label).join(", ");
  const shouldRestart = await askYesNo(`Restart running harnesses now (${names})`, false);
  if (!shouldRestart) {
    results.push({ status: "skip", message: `Harness restart skipped (${names})` });
    return;
  }

  for (const target of restartable) {
    restartHarnessTarget(target, results);
  }
}

function findRestartableHarnesses(selectedHarnesses) {
  const targets = [];
  const seen = new Set();
  for (const harness of selectedHarnesses) {
    const spec = HARNESS_RESTART_SPECS[harness.id];
    if (!spec || seen.has(spec.key)) continue;
    const target = detectRestartTarget(spec);
    if (!target) continue;
    seen.add(spec.key);
    targets.push(target);
  }
  return targets;
}

function detectRestartTarget(spec) {
  if (process.platform === "darwin") return detectMacRestartTarget(spec);
  if (process.platform === "win32") return detectWindowsRestartTarget(spec);
  return detectUnixRestartTarget(spec);
}

function detectMacRestartTarget(spec) {
  if (!spec.macApp || !macAppIsRunning(spec.macApp)) return null;
  return {
    ...spec,
    mode: "mac-app",
  };
}

function detectWindowsRestartTarget(spec) {
  const processName = (spec.processNames || []).find((name) => windowsProcessIsRunning(name));
  if (!processName) return null;
  const launcher = findRestartLauncher(spec);
  if (!launcher) return null;
  return {
    ...spec,
    mode: "windows-process",
    processName,
    launcher,
  };
}

function detectUnixRestartTarget(spec) {
  const processName = (spec.processNames || []).find((name) => unixProcessIsRunning(name));
  if (!processName) return null;
  const command = (spec.commands || []).find((item) => commandExists(item));
  if (!command) return null;
  return {
    ...spec,
    mode: "unix-command",
    processName,
    command,
  };
}

function restartHarnessTarget(target, results) {
  if (DRY_RUN) {
    results.push({ status: "dry", message: `Would restart ${target.label}` });
    return;
  }

  try {
    if (target.mode === "mac-app") restartMacApp(target.macApp);
    else if (target.mode === "windows-process") restartWindowsProcess(target);
    else if (target.mode === "unix-command") restartUnixProcess(target);
    else throw new Error(`unsupported restart mode ${target.mode}`);
    results.push({ status: "ok", message: `${target.label}: restarted` });
  } catch (error) {
    results.push({ status: "warn", message: `${target.label}: could not restart: ${error.message || error}` });
  }
}

function restartMacApp(appName) {
  const quit = spawnSync("osascript", ["-e", `tell application "${escapeAppleScript(appName)}" to quit`], {
    encoding: "utf8",
    stdio: "pipe",
    shell: false,
  });
  if (quit.status !== 0) {
    throw new Error((quit.stderr || quit.stdout || `osascript exited ${quit.status}`).trim());
  }
  const open = spawnSync("open", ["-a", appName], {
    encoding: "utf8",
    stdio: "pipe",
    shell: false,
  });
  if (open.status !== 0) {
    throw new Error((open.stderr || open.stdout || `open exited ${open.status}`).trim());
  }
}

function restartWindowsProcess(target) {
  const exeName = windowsExeName(target.processName);
  const stop = spawnSync("taskkill", ["/IM", exeName, "/T"], {
    encoding: "utf8",
    stdio: "pipe",
    shell: false,
  });
  if (stop.status !== 0 && !String(stop.stderr || stop.stdout).toLowerCase().includes("not found")) {
    throw new Error((stop.stderr || stop.stdout || `taskkill exited ${stop.status}`).trim());
  }
  launchRestartTarget(target.launcher);
}

function restartUnixProcess(target) {
  const stop = spawnSync("pkill", ["-x", target.processName], {
    encoding: "utf8",
    stdio: "pipe",
    shell: false,
  });
  if (stop.status !== 0 && stop.status !== 1) {
    throw new Error((stop.stderr || stop.stdout || `pkill exited ${stop.status}`).trim());
  }
  launchRestartTarget({ command: target.command, args: [] });
}

function launchRestartTarget(launcher) {
  const child = spawn(launcher.command, launcher.args || [], {
    detached: true,
    stdio: "ignore",
    shell: false,
  });
  child.unref();
}

function findRestartLauncher(spec) {
  for (const filePath of spec.windowsPaths || []) {
    if (exists(filePath)) return { command: filePath, args: [] };
  }
  for (const executable of spec.windowsExecutables || []) {
    const found = findOnPath(executable);
    if (found) return { command: found, args: [] };
  }
  for (const command of spec.commands || []) {
    if (commandExists(command)) return { command: spawnCommand(command), args: [] };
  }
  return null;
}

function macAppIsRunning(appName) {
  const result = spawnSync("osascript", ["-e", `application "${escapeAppleScript(appName)}" is running`], {
    encoding: "utf8",
    stdio: "pipe",
    shell: false,
  });
  return result.status === 0 && result.stdout.trim() === "true";
}

function windowsProcessIsRunning(name) {
  const processName = name.replace(/\.exe$/i, "");
  const script = `if (Get-Process -Name '${escapePowerShellSingleQuoted(processName)}' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }`;
  const result = spawnSync("powershell.exe", ["-NoProfile", "-Command", script], {
    stdio: "ignore",
    shell: false,
  });
  return result.status === 0;
}

function unixProcessIsRunning(name) {
  return spawnSync("pgrep", ["-x", name], { stdio: "ignore", shell: false }).status === 0;
}

function windowsExeName(name) {
  return name.toLowerCase().endsWith(".exe") ? name : `${name}.exe`;
}

function findOnPath(command) {
  const pathEnv = process.env.PATH || "";
  const extensions = process.platform === "win32"
    ? (process.env.PATHEXT || ".EXE;.CMD;.BAT;.COM").split(";")
    : [""];
  for (const dir of pathEnv.split(path.delimiter)) {
    if (!dir) continue;
    for (const ext of extensions) {
      const candidate = path.join(dir, process.platform === "win32" && !command.toLowerCase().endsWith(ext.toLowerCase()) ? command + ext : command);
      if (exists(candidate)) return candidate;
    }
  }
  return null;
}

function escapeAppleScript(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function escapePowerShellSingleQuoted(value) {
  return String(value).replace(/'/g, "''");
}

async function configureClaudeCode(serverEntry) {
  if (!commandExists("claude")) {
    throw new Error("Claude Code CLI not found. Run manually: claude mcp add --global " + SERVER_NAME + " -- node " + mcpServerArgs(serverEntry).map(quote).join(" "));
  }
  await run("claude", ["mcp", "add", "--global", SERVER_NAME, "--", "node", ...mcpServerArgs(serverEntry)], { label: "Adding Claude Code MCP server" });
}

async function configureVsCodeCopilot(serverEntry) {
  const payload = JSON.stringify({
    name: SERVER_NAME,
    command: "node",
    args: mcpServerArgs(serverEntry),
  });
  if (!commandExists("code")) {
    throw new Error(`VS Code CLI not found. Run manually: code --add-mcp ${quote(payload)}`);
  }
  await run("code", ["--add-mcp", payload], { label: "Adding VS Code Copilot MCP server" });
}

async function writeMcpServersJson(filePath, serverEntry, extra = {}) {
  const json = await readJson(filePath, {});
  json.mcpServers = json.mcpServers && typeof json.mcpServers === "object" ? json.mcpServers : {};
  json.mcpServers[SERVER_NAME] = { ...mcpServerConfig(serverEntry), ...extra };
  await writeJson(filePath, json);
}

async function writeZcodeJson(filePath, serverEntry) {
  const json = await readJson(filePath, {});
  json.mcp = json.mcp && typeof json.mcp === "object" ? json.mcp : {};
  json.mcp.servers = json.mcp.servers && typeof json.mcp.servers === "object" ? json.mcp.servers : {};
  json.mcp.servers[SERVER_NAME] = mcpServerConfig(serverEntry);
  await writeJson(filePath, json);
}

function printManualMcpRecipe(harness, serverEntry) {
  console.log(`\n${colors.yellow}${harness.name} MCP recipe:${colors.reset}`);
  for (const instruction of harness.config.instructions || []) {
    console.log(`  ${instruction}`);
  }
  console.log(JSON.stringify({ mcpServers: { [SERVER_NAME]: mcpServerConfig(serverEntry) } }, null, 2));
}

function configPaths(config) {
  if (Array.isArray(config.paths)) return config.paths;
  return config.path ? [config.path] : [];
}

async function writeOpencodeJson(filePath, serverEntry) {
  const json = await readJson(filePath, { "$schema": "https://opencode.ai/config.json" });
  json.mcp = json.mcp && typeof json.mcp === "object" ? json.mcp : {};
  json.mcp[SERVER_NAME] = {
    type: "local",
    command: ["node", ...mcpServerArgs(serverEntry)],
    enabled: true,
    // OpenCode gives a local server 5s to list tools by default, which a cold start can miss.
    timeout: 30000,
  };
  await writeJson(filePath, json);
}

async function writeKiloJson(filePath, serverEntry) {
  const json = await readJson(filePath, {});
  json.mcp = json.mcp && typeof json.mcp === "object" ? json.mcp : {};
  json.mcp[SERVER_NAME] = {
    type: "local",
    command: ["node", ...mcpServerArgs(serverEntry)],
    enabled: true,
  };
  await writeJson(filePath, json);
}

async function writeAmpJson(filePath, serverEntry) {
  const json = await readJson(filePath, {});
  json["amp.mcpServers"] =
    json["amp.mcpServers"] && typeof json["amp.mcpServers"] === "object"
      ? json["amp.mcpServers"]
      : {};
  json["amp.mcpServers"][SERVER_NAME] = mcpServerConfig(serverEntry);
  await writeJson(filePath, json);
}

async function writeCodexToml(filePath, serverEntry) {
  let text = exists(filePath) ? await fs.readFile(filePath, "utf8") : "";
  const block = `[mcp_servers.${SERVER_NAME}]\ncommand = "node"\nargs = [${tomlArgs(serverEntry)}]\n`;
  const escapedName = SERVER_NAME.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(`\\n?\\[mcp_servers\\.${escapedName}\\]\\n(?:[^\\[]|\\[(?!mcp_servers\\.))*`, "m");
  text = text.replace(re, "\n");
  text = text.trimEnd();
  text = `${text}${text ? "\n\n" : ""}${block}`;
  await writeText(filePath, text);
}

async function writeContinueYaml(filePath, serverEntry) {
  const markerStart = `# ${SERVER_NAME}:start`;
  const markerEnd = `# ${SERVER_NAME}:end`;
  const block = `${markerStart}\nmcpServers:\n  - name: ${SERVER_NAME}\n    command: node\n    args:\n${yamlArgs(serverEntry)}${markerEnd}\n`;
  let text = exists(filePath) ? await fs.readFile(filePath, "utf8") : "";
  const re = mcpMarkerRegex(SERVER_NAME);
  if (re.test(text)) text = text.replace(re, block);
  else text = `${text.trimEnd()}${text.trimEnd() ? "\n\n" : ""}${block}`;
  await writeText(filePath, text);
}

async function writeGooseYaml(filePath, serverEntry) {
  const markerStart = `# ${SERVER_NAME}:start`;
  const markerEnd = `# ${SERVER_NAME}:end`;
  const block = `${markerStart}\nextensions:\n  ${SERVER_NAME}:\n    command: node\n    args:\n${yamlArgs(serverEntry)}    enabled: true\n    type: stdio\n${markerEnd}\n`;
  let text = exists(filePath) ? await fs.readFile(filePath, "utf8") : "";
  const re = mcpMarkerRegex(SERVER_NAME);
  if (re.test(text)) text = text.replace(re, block);
  else text = `${text.trimEnd()}${text.trimEnd() ? "\n\n" : ""}${block}`;
  await writeText(filePath, text);
}

async function writeVibeToml(filePath, serverEntry) {
  let text = exists(filePath) ? await fs.readFile(filePath, "utf8") : "";
  const block = `[[mcp_servers]]\nname = "${SERVER_NAME}"\ntransport = "stdio"\ncommand = "node"\nargs = [${tomlArgs(serverEntry)}]\n`;
  const re = new RegExp(`\\n?\\[\\[mcp_servers\\]\\]\\nname = "${escapeRe(SERVER_NAME)}"\\n(?:[^\\[]|\\[(?!\\[mcp_servers\\]\\]))*`, "m");
  text = text.replace(re, "\n");
  text = text.trimEnd();
  text = `${text}${text ? "\n\n" : ""}${block}`;
  await writeText(filePath, text);
}

function mcpServerConfig(serverEntry) {
  return { command: "node", args: mcpServerArgs(serverEntry) };
}

function mcpServerArgs(serverEntry) {
  return [serverEntry, "--server-name", SERVER_NAME];
}

function tomlArgs(serverEntry) {
  return mcpServerArgs(serverEntry).map((arg) => `"${tomlString(arg)}"`).join(", ");
}

function yamlArgs(serverEntry) {
  return mcpServerArgs(serverEntry).map((arg) => `      - ${yamlString(arg)}\n`).join("");
}

function mcpMarkerRegex(serverName) {
  const names = [serverName, "roblox-executor-mcp"].map(escapeRe).join("|");
  return new RegExp(`# (?:${names}):start[\\s\\S]*?# (?:${names}):end\\n?`, "m");
}

async function run(command, args, options = {}) {
  if (DRY_RUN) {
    log("dry", `${options.label || command}: ${[command, ...args.map(quote)].join(" ")}`);
    return;
  }
  const label = options.label || [command, ...args].join(" ");
  const spinner = startSpinner(label);
  let output = "";
  await new Promise((resolve, reject) => {
    const commandToRun = spawnCommand(command);
    const useShell = process.platform === "win32" && commandToRun.endsWith(".cmd");
    let child;
    try {
      child = spawn(commandToRun, args, {
        cwd: options.cwd || process.cwd(),
        env: { ...process.env, CI: "true" },
        stdio: ["ignore", "pipe", "pipe"],
        shell: useShell,
        windowsHide: true,
      });
    } catch (error) {
      spinner.stop(false);
      reject(error);
      return;
    }
    child.stdout.on("data", (chunk) => {
      output += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      output += chunk.toString();
    });
    child.on("error", (error) => {
      spinner.stop(false);
      reject(error);
    });
    child.on("close", (code) => {
      if (code === 0) {
        spinner.stop(true);
        resolve();
      } else {
        spinner.stop(false);
        const details = output.trim() ? `\n\n${output.trim()}` : "";
        reject(new Error(`${command} exited with code ${code}${details}`));
      }
    });
  });
}

async function runForeground(command, args, options = {}) {
  if (DRY_RUN) {
    log("dry", `${options.label || command}: ${[command, ...args.map(quote)].join(" ")}`);
    return;
  }

  log("run", options.label || [command, ...args].join(" "));
  await new Promise((resolve, reject) => {
    const commandToRun = spawnCommand(command);
    const useShell = process.platform === "win32" && commandToRun.endsWith(".cmd");
    let child;
    try {
      child = spawn(commandToRun, args, {
        cwd: options.cwd || process.cwd(),
        env: process.env,
        stdio: "inherit",
        shell: useShell,
        windowsHide: false,
      });
    } catch (error) {
      reject(error);
      return;
    }
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited with code ${code}`));
    });
  });
}

async function selectHarnesses(initial) {
  if (!canUseRichPrompts()) {
    return selectHarnessesPlain(initial);
  }

  try {
    return await selectHarnessesOpenTui(initial);
  } catch (error) {
    log("warn", `OpenTUI picker unavailable: ${error.message || error}`);
    log("info", "Falling back to the plain numbered prompt.");
    return selectHarnessesPlain(initial);
  }
}

async function selectHarnessesOpenTui(initial) {
  const { Box, Text, createCliRenderer } = await loadOpenTui();
  const ui = {
    bg: "#050505",
    left: "#0A0A0A",
    right: "#171717",
    topBox: "#101010",
    searchBox: "#1D1D1D",
    divider: "#222222",
    text: "#E7E7E7",
    muted: "#8E8E8E",
    dim: "#626262",
    blue: "#62A0FF",
    peach: "#F4B183",
    green: "#78D98C",
    amber: "#B9853D",
  };
  const state = {
    cursor: 0,
    search: "",
    selected: new Set(initial),
    mode: "list",
    showAll: SHOW_ALL_HARNESSES,
  };

  return await new Promise((resolve, reject) => {
    let settled = false;
    let renderer;
    const cleanup = () => {
      if (settled) return;
      settled = true;
      if (renderer) renderer.destroy();
    };
    const fail = createOpenTuiFailureHandler(cleanup, reject);
    const visibleItems = () => {
      const q = state.search.trim().toLowerCase();
      return pickerHarnesses(state.showAll).filter((h) => !q || `${h.name} ${h.id} ${h.group}`.toLowerCase().includes(q));
    };
    const render = guardOpenTuiHandler(() => {
      if (!renderer || settled) return;
      const items = visibleItems();
      if (state.cursor >= items.length) state.cursor = Math.max(0, items.length - 1);
      const selectedCount = state.selected.size;
      const activeItem = items[state.cursor] || null;
      const baseItems = pickerHarnesses(state.showAll);
      const noDetectedHarnesses = !state.showAll && baseItems.length === 0;
      const activeAvailability = activeItem ? HARNESS_AVAILABILITY.get(activeItem.id) : null;
      const maxVisibleRows = getOpenTuiListHeight(renderer.height);
      const start = getWindowStart(items, state.cursor, maxVisibleRows);
      const windowed = items.slice(start, start + maxVisibleRows);
      const hiddenBelow = Math.max(0, items.length - (start + windowed.length));
      const modeLabel = state.showAll ? "all supported" : `${baseItems.length} detected`;
      const scrollHint = start || hiddenBelow
        ? `${start ? `${start} above` : ""}${start && hiddenBelow ? " · " : ""}${hiddenBelow ? `${hiddenBelow} below` : ""}`
        : "ready";
      const searchText = state.mode === "search"
        ? `/ ${state.search}`
        : state.search
        ? `/ ${state.search}`
        : "/ to search harnesses";
      const searchHelpText = state.mode === "search"
        ? "type to filter   enter done   esc done"
        : "space toggle   enter confirm   esc quit";
      const selectedCountText = `${String(selectedCount).padStart(2, " ")} selected`;
      const viewportWidth = Math.max(60, Number(renderer.width || process.stdout.columns) || 120);
      const leftWidth = Math.max(36, Math.min(Math.floor(viewportWidth * 0.57), viewportWidth - 26));
      const dividerWidth = 1;
      const rightWidth = Math.max(24, viewportWidth - leftWidth - dividerWidth);

      const existingInstallerRoot = renderer.root.getRenderable("installer-root");
      if (existingInstallerRoot) existingInstallerRoot.destroy();
      renderer.root.add(
        Box(
          {
            id: "installer-root",
            width: "100%",
            height: "100%",
            backgroundColor: ui.bg,
            flexDirection: "row",
          },
            Box(
              {
                width: leftWidth,
                height: "100%",
                paddingX: 3,
                paddingY: 2,
                flexDirection: "column",
                overflow: "hidden",
                backgroundColor: ui.left,
              },
              Box(
                {
                  width: "100%",
                  height: 4,
                  flexDirection: "row",
                  backgroundColor: ui.topBox,
                },
                Box({ width: 1, height: "100%", backgroundColor: ui.blue }),
                Box(
                  {
                    flexGrow: 1,
                    height: "100%",
                    paddingX: 2,
                    paddingY: 1,
                    flexDirection: "column",
                  },
                  Text({
                    content: "Roblox Executor MCP",
                    fg: ui.text,
                    attributes: 1,
                    height: 1,
                    truncate: true,
                  }),
                  Text({
                    content: "Select harnesses to use",
                    fg: ui.muted,
                    height: 1,
                    truncate: true,
                  })
                )
              ),
              Box(
                {
                  width: "100%",
                  flexGrow: 1,
                  paddingX: 3,
                  paddingY: 3,
                  flexDirection: "column",
                  backgroundColor: ui.left,
                },
                ...harnessListNodes(Box, Text, windowed, items[state.cursor], state.selected, {
                  palette: ui,
                  emptyMessage: noDetectedHarnesses
                    ? "No local harnesses detected. Install one first, or press s to show all."
                    : "No harnesses match that search.",
                }),
                Box({ flexGrow: 1 }),
                Text({
                  content: state.showAll ? "Showing all harnesses" : "Show other harnesses",
                  fg: ui.text,
                  attributes: 1,
                  height: 1,
                  truncate: true,
                }),
                Text({
                  content: state.showAll ? "press s to return to detected only" : "press s",
                  fg: ui.dim,
                  height: 1,
                  truncate: true,
                })
              ),
              Box(
                {
                  width: "100%",
                  height: 4,
                  flexDirection: "row",
                  backgroundColor: ui.searchBox,
                },
                Box({ width: 1, height: "100%", backgroundColor: ui.blue }),
                Box(
                  {
                    flexGrow: 1,
                    height: "100%",
                    paddingX: 2,
                    paddingY: 1,
                    flexDirection: "column",
                  },
                  Text({
                    content: searchText,
                    fg: state.mode === "search" ? ui.peach : ui.text,
                    attributes: state.mode === "search" ? 1 : 0,
                    height: 1,
                    truncate: true,
                  }),
                  Text({
                    content: searchHelpText,
                    fg: ui.dim,
                    height: 1,
                    truncate: true,
                  })
                )
              )
            ),
            Box({ width: dividerWidth, height: "100%", backgroundColor: ui.divider }),
            Box(
              {
                width: rightWidth,
                height: "100%",
                overflow: "hidden",
                backgroundColor: ui.right,
                paddingX: 3,
                paddingY: 2,
                flexDirection: "column",
              },
              Text({ content: "MCP Installation Selection", fg: ui.text, attributes: 1, height: 1, truncate: true }),
              Box({ height: 2 }),
              Text({ content: "Harnesses", fg: ui.text, attributes: 1, height: 1, truncate: true }),
              Text({ content: `${baseItems.length} detected`, fg: noDetectedHarnesses ? ui.amber : ui.text, height: 1, truncate: true }),
              Text({ content: selectedCountText, fg: selectedCount ? ui.text : ui.muted, height: 1, truncate: true }),
              Box({ height: 2 }),
              Text({ content: "Harness Info", fg: ui.text, attributes: 1, height: 1, truncate: true }),
              ...harnessInfoNodes(Box, Text, activeItem, activeAvailability, noDetectedHarnesses, ui),
              Box({ flexGrow: 1 }),
              Text({ content: `Roblox Executor MCP v${PACKAGE_VERSION}`, fg: ui.text, attributes: 1, height: 1, truncate: true }),
              Text({ content: `${scrollHint} · ${modeLabel}`, fg: ui.dim, height: 1, truncate: true })
            )
        )
      );
      renderer.requestRender();
    }, fail);
    const onKey = guardOpenTuiHandler((key) => {
      if (settled) return;
      const items = visibleItems();
      if (key.name === "c" && key.ctrl) {
        cleanup();
        process.exit(130);
      }
      if (state.mode === "search") {
        if (key.name === "return" || key.name === "escape") state.mode = "list";
        else if (key.name === "backspace") state.search = state.search.slice(0, -1);
        else if (key.sequence && key.sequence.length === 1 && !key.ctrl && !key.meta) state.search += key.sequence;
        state.cursor = 0;
        render();
        return;
      }
      if (key.name === "down") state.cursor = Math.min(items.length - 1, state.cursor + 1);
      else if (key.name === "up") state.cursor = Math.max(0, state.cursor - 1);
      else if (key.name === "pagedown") state.cursor = Math.min(items.length - 1, state.cursor + getOpenTuiListHeight(renderer.height));
      else if (key.name === "pageup") state.cursor = Math.max(0, state.cursor - getOpenTuiListHeight(renderer.height));
      else if (key.name === "home") state.cursor = 0;
      else if (key.name === "end") state.cursor = Math.max(0, items.length - 1);
      else if (key.name === "space" && items[state.cursor]) toggle(state.selected, items[state.cursor].id);
      else if (key.name === "a") {
        const allVisibleSelected = items.every((item) => state.selected.has(item.id));
        for (const item of items) allVisibleSelected ? state.selected.delete(item.id) : state.selected.add(item.id);
      } else if (key.name === "s") {
        state.showAll = !state.showAll;
        state.cursor = 0;
      } else if (key.name === "r") {
        const recommended = pickerHarnesses(state.showAll).filter((item) => item.group === "Recommended");
        const allRecommendedSelected = recommended.every((item) => state.selected.has(item.id));
        for (const item of recommended) allRecommendedSelected ? state.selected.delete(item.id) : state.selected.add(item.id);
      } else if (key.name === "slash" || key.sequence === "/") state.mode = "search";
      else if (key.name === "backspace") state.search = state.search.slice(0, -1);
      else if (key.name === "q" || key.name === "escape") {
        cleanup();
        process.exit(0);
      } else if (key.name === "return") {
        const selected = new Set(state.selected);
        cleanup();
        resolve(selected);
        return;
      }
      render();
    }, fail);

    createCliRenderer(openTuiRendererConfig(ui.bg)).then((created) => {
      if (settled) {
        created.destroy();
        return;
      }
      renderer = created;
      renderer.keyInput.on("keypress", onKey);
      renderer.on("resize", render);
      render();
    }).catch(fail);
  });
}

function guardOpenTuiHandler(handler, fail) {
  return (...args) => {
    try {
      const result = handler(...args);
      if (result && typeof result.then === "function") {
        result.catch(fail);
      }
    } catch (error) {
      fail(error);
    }
  };
}

function createOpenTuiFailureHandler(cleanup, reject) {
  return (error) => {
    OPEN_TUI_DISABLED = true;
    cleanup();
    restoreTerminalAfterOpenTui();
    reject(error);
  };
}

function restoreTerminalAfterOpenTui() {
  showCursor();
  leaveAlternateScreen();
}

async function loadOpenTui() {
  if (!process.versions.bun) {
    throw new Error("run this command with Bun, or pass --plain for the compatibility prompt");
  }

  try {
    return await import("@opentui/core");
  } catch (firstError) {
    const install = spawnSync("bun", ["install", "--ignore-scripts"], {
      cwd: CURRENT_REPO_DIR,
      stdio: "inherit",
      shell: false,
    });
    if (install.status !== 0) {
      throw new Error(`could not install OpenTUI dependency with bun install: ${firstError.message || firstError}`);
    }
    return await import("@opentui/core");
  }
}

function harnessListNodes(Box, Text, items, activeItem, selected, options = {}) {
  const palette = options.palette || {
    bg: "#050505",
    left: "#0A0A0A",
    text: "#E7E7E7",
    muted: "#8E8E8E",
    dim: "#626262",
    peach: "#F4B183",
    green: "#78D98C",
    amber: "#B9853D",
  };
  const nodes = [];
  let currentGroup = "";
  for (const item of items) {
    if (item.group !== currentGroup) {
      currentGroup = item.group;
      nodes.push(Text({
        content: currentGroup,
        fg: palette.muted,
        attributes: 1,
        height: 1,
        truncate: true,
        width: "100%",
      }));
    }
    const active = item === activeItem;
    const checked = selected.has(item.id);
    const flag = item.config?.experimental ? " experimental" : "";
    const rowBg = active ? palette.peach : (palette.left || palette.bg);
    nodes.push(Box(
      {
        width: "100%",
        height: 1,
        flexDirection: "row",
        backgroundColor: rowBg,
      },
      Text({
        content: `  ${item.name}${flag}`,
        fg: active ? palette.bg : checked ? palette.text : palette.muted,
        bg: rowBg,
        attributes: active || checked ? 1 : 0,
        height: 1,
        truncate: true,
      }),
      Box({ flexGrow: 1, height: 1, backgroundColor: rowBg }),
      Text({
        content: checked ? "✓ Enabled " : "          ",
        fg: active ? "#0F5132" : palette.green,
        bg: rowBg,
        height: 1,
        truncate: true,
      })
    ));
  }
  if (!nodes.length) {
    const message = options.emptyMessage || "No harnesses match that search.";
    nodes.push(Text({ content: message, fg: palette.amber, height: 1, truncate: true, width: "100%" }));
  }
  return nodes;
}

function harnessInfoNodes(Box, Text, harness, availability, noDetectedHarnesses, palette) {
  if (!harness) {
    return [
      Text({
        content: "No matches",
        fg: palette.dim,
        attributes: 1,
        height: 1,
        truncate: true,
      }),
      Text({
        content: noDetectedHarnesses
          ? "Install a supported harness first, or press s to show every target."
          : "Clear the search to show harnesses again.",
        fg: noDetectedHarnesses ? palette.amber : palette.muted,
        wrapMode: "word",
        height: 3,
      }),
    ];
  }

  const detected = Boolean(availability?.detected);
  const dotColor = detected ? palette.green : palette.amber;
  const detectionLines = harnessDetectionInfoLines(harness, availability);
  return [
    infoDotRow(Box, Text, palette, dotColor, `Name: ${harness.name}`, palette.text),
    infoDotRow(Box, Text, palette, dotColor, detected ? "Detected" : "Not detected", palette.text),
    Box({ height: 1 }),
    Text({
      content: "Detection Info",
      fg: palette.text,
      attributes: 1,
      height: 1,
      truncate: true,
    }),
    ...detectionLines.map((line) => Text({
      content: `- ${line}`,
      fg: palette.muted,
      height: 1,
      truncate: true,
    })),
  ];
}

function infoDotRow(Box, Text, palette, dotColor, content, contentColor) {
  return Box(
    {
      width: "100%",
      height: 1,
      flexDirection: "row",
      backgroundColor: palette.right,
    },
    Text({ content: "● ", fg: dotColor, height: 1 }),
    Text({ content, fg: contentColor, height: 1, truncate: true })
  );
}

function harnessDetectionInfoLines(harness, availability) {
  const lines = [];
  if (availability?.reason) lines.push(availability.reason);
  if (harness.config?.kind) lines.push(harness.config.kind);
  for (const filePath of configPaths(harness.config).slice(0, 2)) {
    lines.push(shrinkHome(filePath));
  }
  if (harness.config?.experimental) lines.push("experimental path");
  return [...new Set(lines)].slice(0, 5);
}

function getOpenTuiListHeight(rendererHeight) {
  const rows = Number(rendererHeight || process.stdout.rows) || 30;
  return Math.max(4, Math.min(18, rows - 18));
}

function pickerHarnesses(showAll) {
  if (showAll) return ALL_HARNESSES;
  return detectedHarnesses();
}

function detectedHarnesses() {
  return ALL_HARNESSES.filter((harness) => HARNESS_AVAILABILITY.get(harness.id)?.detected);
}

function detectAvailableHarnesses() {
  const map = new Map();
  for (const harness of ALL_HARNESSES) {
    map.set(harness.id, detectHarnessAvailability(harness));
  }
  return map;
}

function detectHarnessAvailability(harness) {
  const checksById = {
    codex: [
      commandCheck("codex"),
      pathCheck(homePath(".codex")),
      configCheck(harness),
    ],
    "claude-code": [
      commandCheck("claude"),
    ],
    opencode: [
      commandCheck("opencode"),
      pathCheck(opencodeConfigDir()),
      configCheck(harness),
    ],
    cursor: [
      commandCheck("cursor"),
      commandCheck("cursor-agent"),
      appCheck("Cursor"),
      pathCheck(homePath(".cursor")),
      configCheck(harness),
    ],
    trae: [
      appCheck("Trae"),
      configCheck(harness),
    ],
    antigravity: [
      commandCheck("antigravity"),
      appCheck("Antigravity"),
      pathCheck(homePath(".gemini", "antigravity")),
      configCheck(harness),
    ],
    "gemini-cli": [
      commandCheck("gemini"),
      pathCheck(homePath(".gemini")),
      configCheck(harness),
    ],
    "github-copilot": [
      pathCheck(homePath(".copilot")),
      extensionCheck("github.copilot"),
      configCheck(harness),
    ],
    "vscode-copilot": [
      commandCheck("code"),
      appCheck("Visual Studio Code"),
      extensionCheck("github.copilot"),
    ],
    amp: [
      commandCheck("amp"),
      extensionCheck("amp"),
    ],
    blackbox: [
      extensionCheck("blackboxapp.blackbox"),
      extensionCheck("blackbox"),
    ],
    cline: [
      pathCheck(homePath(".cline")),
      extensionCheck("saoudrizwan.claude-dev"),
      extensionCheck("cline"),
      configCheck(harness),
    ],
    "claude-desktop": [
      appCheck("Claude"),
      configCheck(harness),
    ],
    "deep-agents": [
      pathCheck(homePath(".deepagents")),
      configCheck(harness),
    ],
    "kimi-cli": [
      commandCheck("kimi"),
      pathCheck(homePath(".kimi")),
      configCheck(harness),
    ],
    augment: [
      commandCheck("augment"),
      pathCheck(homePath(".augment")),
      extensionCheck("augment"),
      configCheck(harness),
    ],
    continue: [
      commandCheck("continue"),
      pathCheck(homePath(".continue")),
      extensionCheck("continue"),
      configCheck(harness),
    ],
    "devin-terminal": [
      commandCheck("devin"),
      pathCheck(homePath(".config", "devin")),
      configCheck(harness),
    ],
    goose: [
      commandCheck("goose"),
      pathCheck(path.dirname(gooseConfigPath())),
      configCheck(harness),
    ],
    "iflow-cli": [
      commandCheck("iflow"),
      pathCheck(homePath(".iflow")),
      configCheck(harness),
    ],
    "kilo-code": [
      commandCheck("kilo"),
      pathCheck(homePath(".config", "kilo")),
      extensionCheck("kilo"),
      configCheck(harness),
    ],
    "kiro-cli": [
      commandCheck("kiro"),
      pathCheck(homePath(".kiro")),
      configCheck(harness),
    ],
    "mistral-vibe": [
      commandCheck("vibe"),
      pathCheck(homePath(".vibe")),
      configCheck(harness),
    ],
    openhands: [
      commandCheck("openhands"),
      pathCheck(homePath(".openhands")),
      configCheck(harness),
    ],
    "qwen-code": [
      commandCheck("qwen"),
      pathCheck(homePath(".qwen")),
      configCheck(harness),
    ],
    "rovo-dev": [
      commandCheck("rovo"),
      pathCheck(homePath(".rovodev")),
      configCheck(harness),
    ],
    "roo-code": [
      pathCheck(path.dirname(vscodeGlobalStoragePath("rooveterinaryinc.roo-cline", "settings", "mcp_settings.json"))),
      extensionCheck("rooveterinaryinc.roo-cline"),
      extensionCheck("roo-cline"),
      configCheck(harness),
    ],
    "tabnine-cli": [
      commandCheck("tabnine"),
      pathCheck(homePath(".tabnine")),
      configCheck(harness),
    ],
    windsurf: [
      commandCheck("windsurf"),
      appCheck("Windsurf"),
      pathCheck(homePath(".codeium", "windsurf")),
      configCheck(harness),
    ],
    zcode: [
      commandCheck("zcode"),
      appCheck("ZCode"),
      pathCheck(homePath(".zcode")),
      configCheck(harness),
    ],
    manual: [],
  };

  for (const check of checksById[harness.id] || [configCheck(harness)]) {
    const result = check();
    if (result) return { detected: true, reason: result };
  }
  return { detected: false, reason: "" };
}

function commandCheck(command) {
  return () => commandExists(command) ? `command ${command}` : "";
}

function pathCheck(filePath) {
  return () => exists(filePath) ? shrinkHome(filePath) : "";
}

function configCheck(harness) {
  return () => {
    const found = configPaths(harness.config).find((filePath) => exists(filePath));
    return found ? `config ${shrinkHome(found)}` : "";
  };
}

function appCheck(name) {
  return () => {
    for (const filePath of appCandidatePaths(name)) {
      if (exists(filePath)) return shrinkHome(filePath);
    }
    return "";
  };
}

function extensionCheck(fragment) {
  return () => {
    const found = findEditorExtension(fragment);
    return found ? `extension ${found}` : "";
  };
}

function appCandidatePaths(name) {
  if (process.platform === "darwin") {
    return [
      path.join("/Applications", `${name}.app`),
      path.join(os.homedir(), "Applications", `${name}.app`),
    ];
  }
  if (process.platform === "win32") {
    return [
      path.join(process.env.LOCALAPPDATA || homePath("AppData", "Local"), "Programs", name),
      path.join(process.env.PROGRAMFILES || "C:\\Program Files", name),
      path.join(process.env["PROGRAMFILES(X86)"] || "C:\\Program Files (x86)", name),
    ];
  }
  return [
    path.join(process.env.XDG_CONFIG_HOME || homePath(".config"), name.toLowerCase()),
    path.join(process.env.XDG_DATA_HOME || homePath(".local", "share"), name.toLowerCase()),
  ];
}

function findEditorExtension(fragment) {
  const q = fragment.toLowerCase();
  const roots = [
    homePath(".vscode", "extensions"),
    homePath(".cursor", "extensions"),
    homePath(".windsurf", "extensions"),
    homePath(".codeium", "windsurf", "extensions"),
  ];
  for (const root of roots) {
    if (!exists(root)) continue;
    try {
      const match = fsSync.readdirSync(root).find((entry) => entry.toLowerCase().includes(q));
      if (match) return match;
    } catch {
      // Ignore unreadable editor extension folders.
    }
  }
  return "";
}

async function selectHarnessesPlain(initial) {
  const selected = new Set(initial);
  const harnesses = pickerHarnesses(SHOW_ALL_HARNESSES);
  const hiddenCount = Math.max(0, ALL_HARNESSES.length - harnesses.length);
  console.log(`${colors.cyan}${colors.bold}Roblox Executor MCP${colors.reset}`);
  if (!harnesses.length) {
    console.log(`${colors.yellow}No local AI harnesses were detected.${colors.reset}`);
    console.log(`${colors.gray}Install Codex, Claude Code, Cursor, VS Code, or another supported harness first.${colors.reset}`);
    console.log(`${colors.gray}If detection missed your install, rerun with --show-all-harnesses to list every supported target.${colors.reset}\n`);
    return selected;
  }
  if (hiddenCount > 0) {
    console.log(`${colors.gray}Showing ${harnesses.length} detected harnesses. Use --show-all-harnesses to list all ${ALL_HARNESSES.length}. Press Enter for none.${colors.reset}\n`);
  } else {
    console.log(`${colors.gray}Choose harnesses by number. Press Enter for none.${colors.reset}\n`);
  }

  let index = 1;
  const numbered = [];
  let currentGroup = "";
  for (const harness of harnesses) {
    if (harness.group !== currentGroup) {
      currentGroup = harness.group;
      console.log(`${colors.bold}${currentGroup}${colors.reset}`);
    }
    numbered.push(harness);
    const experimental = harness.config?.experimental ? ` ${colors.yellow}(experimental)${colors.reset}` : "";
    const availability = HARNESS_AVAILABILITY.get(harness.id);
    const reason = availability?.detected ? ` ${colors.gray}- ${availability.reason}${colors.reset}` : "";
    console.log(`  ${String(index).padStart(2)}. ${harness.name}${experimental}${reason}`);
    index += 1;
  }

  const answer = await askInput(
    "Harness numbers, comma-separated, or 'all'",
    ""
  );
  const raw = answer.trim().toLowerCase();
  if (!raw) return selected;
  if (raw === "all") {
    for (const harness of harnesses) selected.add(harness.id);
    return selected;
  }

  for (const part of raw.split(/[,\s]+/)) {
    const n = Number(part);
    if (!Number.isInteger(n) || n < 1 || n > numbered.length) continue;
    selected.add(numbered[n - 1].id);
  }

  return selected;
}

async function askInput(label, fallback) {
  if (canUseRichPrompts()) {
    try {
      return await askInputOpenTui(label, fallback);
    } catch (error) {
      log("warn", `OpenTUI input unavailable: ${error.message || error}`);
      log("info", "Falling back to the plain numbered prompt.");
    }
  }

  showCursor();
  const fallbackText = fallback ? ` ${colors.gray}(${fallback})${colors.reset}` : "";
  const answer = await prompt(`${colors.bold}${label}${colors.reset}${fallbackText}: `);
  hideCursor();
  return answer.trim() || fallback;
}

async function askYesNo(label, fallback) {
  if (canUseRichPrompts()) {
    try {
      return await askYesNoOpenTui(label, fallback);
    } catch (error) {
      log("warn", `OpenTUI prompt unavailable: ${error.message || error}`);
      log("info", "Falling back to the plain prompt.");
    }
  }

  showCursor();
  const answer = await prompt(`${colors.bold}${label}${colors.reset} ${colors.gray}${fallback ? "(Y/n)" : "(y/N)"}${colors.reset}: `);
  hideCursor();
  if (!answer.trim()) return fallback;
  return /^y(es)?$/i.test(answer.trim());
}

async function askChoice(label, options, fallbackKey) {
  if (canUseRichPrompts()) {
    try {
      return await askChoiceOpenTui(label, options, fallbackKey);
    } catch (error) {
      log("warn", `OpenTUI choice prompt unavailable: ${error.message || error}`);
      log("info", "Falling back to the plain prompt.");
    }
  }

  console.log(`\n${colors.cyan}${label}:${colors.reset}`);
  for (const option of options) {
    console.log(`  ${option.key}. ${option.title} ${colors.gray}${option.detail}${colors.reset}`);
  }
  showCursor();
  const answer = await prompt(`${colors.bold}Choice${colors.reset} ${colors.gray}(${fallbackKey})${colors.reset}: `);
  hideCursor();
  return answer.trim() || fallbackKey;
}

async function askYesNoOpenTui(label, fallback) {
  const { Box, Text, createCliRenderer } = await loadOpenTui();
  const copy = yesNoDialogCopy(label, fallback);
  const palette = {
    bg: "#050505",
    panel: "#171717",
    panelDark: "#101010",
    text: "#E7E7E7",
    muted: "#8E8E8E",
    dim: "#626262",
    blue: "#62A0FF",
    peach: "#F4B183",
  };
  const state = {
    choice: fallback ? "yes" : "no",
  };

  return await new Promise((resolve, reject) => {
    let settled = false;
    let renderer;
    const cleanup = () => {
      if (settled) return;
      settled = true;
      if (renderer) renderer.destroy();
    };
    const finish = (value) => {
      cleanup();
      resolve(value);
    };
    const fail = createOpenTuiFailureHandler(cleanup, reject);
    const render = guardOpenTuiHandler(() => {
      if (!renderer || settled) return;
      const viewportWidth = Math.max(60, Number(renderer.width || process.stdout.columns) || 100);
      const viewportHeight = Math.max(20, Number(renderer.height || process.stdout.rows) || 30);
      const dialogWidth = Math.max(54, Math.min(82, viewportWidth - 8));
      const dialogHeight = 14;
      const topPad = Math.max(1, Math.floor((viewportHeight - dialogHeight) / 2));
      const sidePad = Math.max(0, Math.floor((viewportWidth - dialogWidth) / 2));
      const yesActive = state.choice === "yes";
      const noActive = state.choice === "no";

      const existingYesNoRoot = renderer.root.getRenderable("yes-no-dialog-root");
      if (existingYesNoRoot) existingYesNoRoot.destroy();
      renderer.root.add(
        Box(
          {
            id: "yes-no-dialog-root",
            width: "100%",
            height: "100%",
            backgroundColor: palette.bg,
            flexDirection: "column",
          },
          Box({ height: topPad, width: "100%", backgroundColor: palette.bg }),
          Box(
            {
              width: "100%",
              height: dialogHeight,
              flexDirection: "row",
              backgroundColor: palette.bg,
            },
            Box({ width: sidePad, height: "100%", backgroundColor: palette.bg }),
            Box(
              {
                width: dialogWidth,
                height: "100%",
                backgroundColor: palette.panel,
                flexDirection: "row",
              },
              Box({ width: 1, height: "100%", backgroundColor: palette.blue }),
              Box(
                {
                  flexGrow: 1,
                  height: "100%",
                  paddingX: 2,
                  paddingY: 1,
                  flexDirection: "column",
                },
                Box(
                  {
                    width: "100%",
                    height: 2,
                    flexDirection: "column",
                    backgroundColor: palette.panel,
                  },
                  Box(
                    {
                      width: "100%",
                      height: 1,
                      flexDirection: "row",
                      backgroundColor: palette.panel,
                    },
                    Text({ content: copy.title, fg: palette.text, attributes: 1, height: 1, truncate: true }),
                    Box({ flexGrow: 1, height: 1, backgroundColor: palette.panel }),
                    Text({ content: "esc", fg: palette.muted, height: 1, truncate: true })
                  ),
                  Text({ content: "left/right or tab to choose   enter to confirm   y/n works", fg: palette.dim, height: 1, truncate: true })
                ),
                Box({ height: 1 }),
                Text({ content: copy.message, fg: palette.text, attributes: 1, height: 1, truncate: true }),
                Text({ content: copy.detail, fg: palette.muted, wrapMode: "word", height: 3 }),
                Box({ flexGrow: 1 }),
                Box(
                  {
                    width: "100%",
                    height: 1,
                    flexDirection: "row",
                    backgroundColor: palette.panel,
                  },
                  Box({ flexGrow: 1, height: 1, backgroundColor: palette.panel }),
                  dialogButton(Text, palette, copy.noLabel, noActive),
                  Text({ content: "  ", fg: palette.muted, bg: palette.panel, height: 1 }),
                  dialogButton(Text, palette, copy.yesLabel, yesActive)
                )
              )
            )
          )
        )
      );
      renderer.requestRender();
    }, fail);
    const onKey = guardOpenTuiHandler((key) => {
      if (settled) return;
      if (key.name === "c" && key.ctrl) {
        cleanup();
        process.exit(130);
      }
      if (key.name === "left" || key.name === "right" || key.name === "tab") {
        state.choice = state.choice === "yes" ? "no" : "yes";
      } else if (key.name === "y" || key.sequence === "y" || key.sequence === "Y") {
        finish(true);
        return;
      } else if (key.name === "n" || key.sequence === "n" || key.sequence === "N") {
        finish(false);
        return;
      } else if (key.name === "return") {
        finish(state.choice === "yes");
        return;
      } else if (key.name === "escape" || key.name === "q") {
        finish(fallback);
        return;
      }
      render();
    }, fail);

    createCliRenderer(openTuiRendererConfig(palette.bg)).then((created) => {
      if (settled) {
        created.destroy();
        return;
      }
      renderer = created;
      renderer.keyInput.on("keypress", onKey);
      renderer.on("resize", render);
      hideCursor();
      render();
    }).catch(fail);
  });
}

function dialogButton(Text, palette, label, active) {
  return Text({
    content: ` ${label} `,
    fg: active ? palette.bg : palette.muted,
    bg: active ? palette.peach : palette.panel,
    attributes: active ? 1 : 0,
    height: 1,
    truncate: true,
  });
}

async function askChoiceOpenTui(label, options, fallbackKey) {
  const { Box, Text, createCliRenderer } = await loadOpenTui();
  const palette = {
    bg: "#050505",
    panel: "#171717",
    panelDark: "#101010",
    text: "#E7E7E7",
    muted: "#8E8E8E",
    dim: "#626262",
    blue: "#62A0FF",
    peach: "#F4B183",
  };
  const fallbackIndex = Math.max(0, options.findIndex((option) => option.key === fallbackKey));
  const state = {
    index: fallbackIndex,
  };

  return await new Promise((resolve, reject) => {
    let settled = false;
    let renderer;
    const cleanup = () => {
      if (settled) return;
      settled = true;
      if (renderer) renderer.destroy();
    };
    const finish = (key) => {
      cleanup();
      resolve(key);
    };
    const fail = createOpenTuiFailureHandler(cleanup, reject);
    const render = guardOpenTuiHandler(() => {
      if (!renderer || settled) return;
      const viewportWidth = Math.max(70, Number(renderer.width || process.stdout.columns) || 110);
      const viewportHeight = Math.max(22, Number(renderer.height || process.stdout.rows) || 30);
      const dialogWidth = Math.max(64, Math.min(100, viewportWidth - 8));
      const dialogHeight = 16;
      const topPad = Math.max(1, Math.floor((viewportHeight - dialogHeight) / 2));
      const sidePad = Math.max(0, Math.floor((viewportWidth - dialogWidth) / 2));
      const selected = options[state.index] || options[fallbackIndex] || options[0];

      const existingChoiceRoot = renderer.root.getRenderable("choice-dialog-root");
      if (existingChoiceRoot) existingChoiceRoot.destroy();
      renderer.root.add(
        Box(
          {
            id: "choice-dialog-root",
            width: "100%",
            height: "100%",
            backgroundColor: palette.bg,
            flexDirection: "column",
          },
          Box({ height: topPad, width: "100%", backgroundColor: palette.bg }),
          Box(
            {
              width: "100%",
              height: dialogHeight,
              flexDirection: "row",
              backgroundColor: palette.bg,
            },
            Box({ width: sidePad, height: "100%", backgroundColor: palette.bg }),
            Box(
              {
                width: dialogWidth,
                height: "100%",
                backgroundColor: palette.panel,
                flexDirection: "row",
              },
              Box({ width: 1, height: "100%", backgroundColor: palette.blue }),
              Box(
                {
                  flexGrow: 1,
                  height: "100%",
                  paddingX: 2,
                  paddingY: 1,
                  flexDirection: "column",
                },
                Box(
                  {
                    width: "100%",
                    height: 2,
                    flexDirection: "column",
                    backgroundColor: palette.panel,
                  },
                  Box(
                    {
                      width: "100%",
                      height: 1,
                      flexDirection: "row",
                      backgroundColor: palette.panel,
                    },
                    Text({ content: "Roblox Connection", fg: palette.text, attributes: 1, height: 1, truncate: true }),
                    Box({ flexGrow: 1, height: 1, backgroundColor: palette.panel }),
                    Text({ content: "esc", fg: palette.muted, height: 1, truncate: true })
                  ),
                  Text({ content: "left/right or tab to choose   enter to confirm   1/2/3 works", fg: palette.dim, height: 1, truncate: true })
                ),
                Box({ height: 1 }),
                Text({ content: label, fg: palette.text, attributes: 1, height: 1, truncate: true }),
                Text({ content: selected ? `${selected.title}: ${selected.detail}` : "", fg: palette.muted, wrapMode: "word", height: 3 }),
                Box({ flexGrow: 1 }),
                Box(
                  {
                    width: "100%",
                    height: 1,
                    flexDirection: "row",
                    backgroundColor: palette.panel,
                  },
                  Box({ flexGrow: 1, height: 1, backgroundColor: palette.panel }),
                  ...choiceButtons(Text, palette, options, state.index)
                )
              )
            )
          )
        )
      );
      renderer.requestRender();
    }, fail);
    const onKey = guardOpenTuiHandler((key) => {
      if (settled) return;
      if (key.name === "c" && key.ctrl) {
        cleanup();
        process.exit(130);
      }
      if (key.name === "left") {
        state.index = (state.index - 1 + options.length) % options.length;
      } else if (key.name === "right" || key.name === "tab") {
        state.index = (state.index + 1) % options.length;
      } else if (key.name === "return") {
        finish((options[state.index] || options[fallbackIndex] || options[0]).key);
        return;
      } else if (key.name === "escape" || key.name === "q") {
        finish(fallbackKey);
        return;
      } else if (key.sequence) {
        const directIndex = options.findIndex((option) => option.key === key.sequence);
        if (directIndex !== -1) {
          finish(options[directIndex].key);
          return;
        }
      }
      render();
    }, fail);

    createCliRenderer(openTuiRendererConfig(palette.bg)).then((created) => {
      if (settled) {
        created.destroy();
        return;
      }
      renderer = created;
      renderer.keyInput.on("keypress", onKey);
      renderer.on("resize", render);
      hideCursor();
      render();
    }).catch(fail);
  });
}

function choiceButtons(Text, palette, options, activeIndex) {
  const nodes = [];
  for (let index = 0; index < options.length; index += 1) {
    if (index > 0) nodes.push(Text({ content: "  ", fg: palette.muted, bg: palette.panel, height: 1 }));
    nodes.push(dialogButton(Text, palette, options[index].title, index === activeIndex));
  }
  return nodes;
}

async function askInputOpenTui(label, fallback = "") {
  const { Box, Text, createCliRenderer } = await loadOpenTui();
  const copy = inputDialogCopy(label, fallback);
  const palette = {
    bg: "#050505",
    panel: "#171717",
    input: "#1D1D1D",
    text: "#E7E7E7",
    muted: "#8E8E8E",
    dim: "#626262",
    blue: "#62A0FF",
    peach: "#F4B183",
  };
  const state = {
    value: "",
  };

  return await new Promise((resolve, reject) => {
    let settled = false;
    let renderer;
    const cleanup = () => {
      if (settled) return;
      settled = true;
      if (renderer) renderer.destroy();
    };
    const finish = () => {
      const value = state.value.trim() || fallback;
      cleanup();
      resolve(value);
    };
    const fail = createOpenTuiFailureHandler(cleanup, reject);
    const render = guardOpenTuiHandler(() => {
      if (!renderer || settled) return;
      const viewportWidth = Math.max(60, Number(renderer.width || process.stdout.columns) || 100);
      const viewportHeight = Math.max(20, Number(renderer.height || process.stdout.rows) || 30);
      const dialogWidth = Math.max(54, Math.min(82, viewportWidth - 8));
      const dialogHeight = 14;
      const topPad = Math.max(1, Math.floor((viewportHeight - dialogHeight) / 2));
      const sidePad = Math.max(0, Math.floor((viewportWidth - dialogWidth) / 2));
      const displayValue = state.value || fallback || "";
      const inputPrefix = state.value ? "> " : "default ";
      const inputColor = state.value ? palette.text : palette.muted;

      const existingInputRoot = renderer.root.getRenderable("input-dialog-root");
      if (existingInputRoot) existingInputRoot.destroy();
      renderer.root.add(
        Box(
          {
            id: "input-dialog-root",
            width: "100%",
            height: "100%",
            backgroundColor: palette.bg,
            flexDirection: "column",
          },
          Box({ height: topPad, width: "100%", backgroundColor: palette.bg }),
          Box(
            {
              width: "100%",
              height: dialogHeight,
              flexDirection: "row",
              backgroundColor: palette.bg,
            },
            Box({ width: sidePad, height: "100%", backgroundColor: palette.bg }),
            Box(
              {
                width: dialogWidth,
                height: "100%",
                backgroundColor: palette.panel,
                flexDirection: "row",
              },
              Box({ width: 1, height: "100%", backgroundColor: palette.blue }),
              Box(
                {
                  flexGrow: 1,
                  height: "100%",
                  paddingX: 2,
                  paddingY: 1,
                  flexDirection: "column",
                },
                Box(
                  {
                    width: "100%",
                    height: 2,
                    flexDirection: "column",
                    backgroundColor: palette.panel,
                  },
                  Box(
                    {
                      width: "100%",
                      height: 1,
                      flexDirection: "row",
                      backgroundColor: palette.panel,
                    },
                    Text({ content: copy.title, fg: palette.text, attributes: 1, height: 1, truncate: true }),
                    Box({ flexGrow: 1, height: 1, backgroundColor: palette.panel }),
                    Text({ content: "esc", fg: palette.muted, height: 1, truncate: true })
                  ),
                  Text({ content: "type a value   enter to confirm   esc uses default", fg: palette.dim, height: 1, truncate: true })
                ),
                Box({ height: 1 }),
                Text({ content: copy.message, fg: palette.text, attributes: 1, height: 1, truncate: true }),
                Text({ content: copy.detail, fg: palette.muted, wrapMode: "word", height: 3 }),
                Box({ flexGrow: 1 }),
                Box(
                  {
                    width: "100%",
                    height: 3,
                    flexDirection: "row",
                    backgroundColor: palette.input,
                  },
                  Box({ width: 1, height: "100%", backgroundColor: palette.blue }),
                  Box(
                    {
                      flexGrow: 1,
                      height: "100%",
                      paddingX: 2,
                      paddingY: 1,
                      flexDirection: "column",
                    },
                    Text({
                      content: `${inputPrefix}${displayValue}${state.value ? "" : " (press Enter)"}`,
                      fg: inputColor,
                      height: 1,
                      truncate: true,
                    })
                  )
                )
              )
            )
          )
        )
      );
      renderer.requestRender();
    }, fail);
    const onKey = guardOpenTuiHandler((key) => {
      if (settled) return;
      if (key.name === "c" && key.ctrl) {
        cleanup();
        process.exit(130);
      }
      if (key.name === "return") {
        finish();
        return;
      }
      if (key.name === "escape") {
        state.value = "";
        finish();
        return;
      }
      if (key.name === "backspace") {
        state.value = state.value.slice(0, -1);
      } else if (key.sequence && key.sequence.length === 1 && !key.ctrl && !key.meta) {
        state.value += key.sequence;
      }
      render();
    }, fail);

    createCliRenderer(openTuiRendererConfig(palette.bg)).then((created) => {
      if (settled) {
        created.destroy();
        return;
      }
      renderer = created;
      renderer.keyInput.on("keypress", onKey);
      renderer.on("resize", render);
      hideCursor();
      render();
    }).catch(fail);
  });
}

function inputDialogCopy(label, fallback) {
  if (/Connection target/i.test(label)) {
    return {
      title: "Roblox Connection",
      message: "How should Roblox reach this MCP server?",
      detail: "Type 1 for this computer, 2 for local network, or 3 for Tailscale authorized machines.",
    };
  }
  if (/bridge address/i.test(label)) {
    return {
      title: "Bridge Address",
      message: label,
      detail: fallback
        ? `Press Enter to use ${fallback}, or type another host:port address.`
        : "Type the host:port address for this connection path.",
    };
  }
  if (/Local machine IP|LAN IP|Roblox to reach/i.test(label)) {
    return {
      title: "Roblox Connection",
      message: "What IP should Roblox connect to?",
      detail: `Use the detected address unless Roblox is on another network interface. Default: ${fallback}`,
    };
  }
  if (/Autoexec target/i.test(label)) {
    return {
      title: "Autoexec Target",
      message: "Where should the loader be installed?",
      detail: "Type target numbers separated by commas, or press Enter to install to all detected executors.",
    };
  }
  if (/Harness numbers/i.test(label)) {
    return {
      title: "Harness Selection",
      message: "Which harnesses should be configured?",
      detail: "Type numbers separated by commas, type all, or press Enter to skip.",
    };
  }
  return {
    title: "Installer Input",
    message: label,
    detail: fallback ? `Press Enter to use the default: ${fallback}` : "Type a value, then press Enter.",
  };
}

function yesNoDialogCopy(label, fallback) {
  if (/Roblox on another machine/i.test(label)) {
    return {
      title: "Roblox Connection",
      message: "Will Roblox run on a different computer?",
      detail: "Choose No if Roblox and this installer are on the same Mac. Choose Yes only if Roblox needs to connect over your local network.",
      noLabel: "No, same computer",
      yesLabel: "Yes, another computer",
    };
  }
  if (/Pull latest/i.test(label)) {
    return {
      title: "Update Before Install",
      message: "Check for the newest installer code first?",
      detail: "This runs git pull before building. Choose No if you want to use the files already on this machine.",
      noLabel: "Skip",
      yesLabel: "Update",
    };
  }
  if (/Ollama|semantic/i.test(label)) {
    return {
      title: "Optional Search Setup",
      message: "Set up local semantic search?",
      detail: "This installs or configures Ollama with embeddinggemma. It is optional and can take extra disk space and time.",
      noLabel: "Skip",
      yesLabel: "Set up",
    };
  }
  if (/autoexec/i.test(label)) {
    return {
      title: "Autoexec Loader",
      message: "Install the Roblox loader into autoexec?",
      detail: "This can make supported executors load the bridge automatically. Choose Skip if you prefer to paste the loader manually.",
      noLabel: "Skip",
      yesLabel: "Install",
    };
  }
  return {
    title: "Installer Question",
    message: label,
    detail: fallback ? "Press Enter to keep the recommended Yes choice." : "Press Enter to keep the recommended No choice.",
    noLabel: "No",
    yesLabel: "Yes",
  };
}

function prompt(query) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(query, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

function printBanner() {
  const title = "Roblox Executor MCP";
  const subtitle = "provider setup console";
  const hint = "Pick clients, build this repo, write MCP config where known.";
  const width = Math.max(62, visibleLength(title) + visibleLength(subtitle) + 5, visibleLength(hint) + 2);
  if (ASCII_MODE) {
    console.log(colors.cyan + `+${"-".repeat(width)}+` + colors.reset);
    console.log(colors.cyan + "|" + colors.reset + padAnsi(` ${colors.bold}${title}${colors.reset}  ${colors.gray}${subtitle}${colors.reset}`, width) + colors.cyan + "|" + colors.reset);
    console.log(colors.cyan + `+${"-".repeat(width)}+` + colors.reset);
  } else {
    console.log(colors.cyan + `╭${"─".repeat(width)}╮` + colors.reset);
    console.log(colors.cyan + "│" + colors.reset + padAnsi(` ${colors.bold}${title}${colors.reset}  ${colors.gray}${subtitle}${colors.reset}`, width) + colors.cyan + "│" + colors.reset);
    console.log(colors.cyan + `╰${"─".repeat(width)}╯` + colors.reset);
  }
  console.log(` ${colors.gray}${hint}${colors.reset}\n`);
}

function formatSelection(selected) {
  const names = ALL_HARNESSES.filter((h) => selected.has(h.id)).map((h) => h.name);
  if (!names.length) return colors.gray + "none" + colors.reset;
  return names.join(", ");
}

function getHarnessWindowHeight() {
  const rows = Number(process.stdout.rows) || 30;
  const reservedRows = 16;
  return Math.max(5, Math.min(18, rows - reservedRows));
}

function getWindowStart(items, cursor, maxVisibleRows) {
  if (items.length <= maxVisibleRows) return 0;
  const half = Math.floor(maxVisibleRows / 2);
  const maxStart = Math.max(0, items.length - maxVisibleRows);
  return Math.min(Math.max(0, cursor - half), maxStart);
}

function section(title) {
  console.log(`\n${colors.cyan}${colors.bold}${title}${colors.reset}`);
}

function log(status, message) {
  const icon = ASCII_MODE || PLAIN_MODE
    ? {
      ok: "[OK]",
      warn: "[!]",
      info: "[i]",
      run: ">",
      skip: "[-]",
      dry: "[dry]",
    }[status] || "[-]"
    : {
      ok: `${colors.green}◆${colors.reset}`,
      warn: `${colors.yellow}◆${colors.reset}`,
      info: `${colors.cyan}◇${colors.reset}`,
      run: `${colors.purple}●${colors.reset}`,
      skip: `${colors.gray}◇${colors.reset}`,
      dry: `${colors.yellow}◇${colors.reset}`,
    }[status] || `${colors.gray}◇${colors.reset}`;
  console.log(`${icon} ${message}`);
}

function startSpinner(label) {
  const frames = ASCII_MODE ? ["|", "/", "-", "\\"] : ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  let index = 0;
  let active = process.stdout.isTTY && !PLAIN_MODE;
  if (!active) {
    log("run", label);
    return { stop: (ok) => ok && undefined };
  }

  const render = () => {
    process.stdout.write(`\r${colors.purple}${frames[index++ % frames.length]}${colors.reset} ${label} ${progressBar(index)}`);
  };
  render();
  const timer = setInterval(render, 80);
  return {
    stop(ok) {
      if (!active) return;
      active = false;
      clearInterval(timer);
      const icon = ok ? `${colors.green}${ASCII_MODE ? "[OK]" : "◆"}${colors.reset}` : `${colors.red}${ASCII_MODE ? "[!]" : "◆"}${colors.reset}`;
      process.stdout.write(`\r\x1b[2K${icon} ${label}\n`);
    },
  };
}

function progressBar(step) {
  const width = 14;
  const filled = step % (width + 1);
  return `${colors.gray}[${colors.reset}${colors.cyan}${"=".repeat(filled)}${colors.reset}${colors.gray}${" ".repeat(width - filled)}]${colors.reset}`;
}

async function readJson(filePath, fallback) {
  if (!exists(filePath)) return structuredClone(fallback);
  const raw = await fs.readFile(filePath, "utf8");
  if (!raw.trim()) return structuredClone(fallback);
  try {
    return JSON.parse(stripJsonComments(raw));
  } catch (error) {
    throw new Error(`Could not parse ${filePath}: ${error.message}`);
  }
}

async function writeJson(filePath, value) {
  await writeText(filePath, JSON.stringify(value, null, 2) + "\n");
}

async function writeText(filePath, text) {
  if (DRY_RUN) {
    log("dry", `Would write ${filePath}`);
    return;
  }
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  if (exists(filePath)) await fs.copyFile(filePath, `${filePath}.bak`);
  await fs.writeFile(filePath, text, "utf8");
}

function exists(filePath) {
  return fsSync.existsSync(filePath);
}

function isGitRepository(dir) {
  return exists(path.join(dir, ".git"));
}

function commandExists(command) {
  const probe = process.platform === "win32" ? "where" : "which";
  return spawnSync(probe, [command], { stdio: "ignore", shell: false }).status === 0;
}

function spawnCommand(command) {
  if (process.platform !== "win32") return command;
  if (command.endsWith(".cmd") || command.endsWith(".exe")) return command;
  if (["npm", "pnpm", "yarn", "code", "claude"].includes(command)) return `${command}.cmd`;
  return command;
}

function canUseRichPrompts() {
  if (PLAIN_MODE || NO_OPENTUI || OPEN_TUI_DISABLED || LEGACY_WINDOWS_CONSOLE) return false;
  if (!process.stdin.isTTY || !process.stdout.isTTY || !process.versions.bun) return false;
  return true;
}

function openTuiRendererConfig(backgroundColor) {
  const compatibilityMode = ASCII_MODE || LEGACY_WINDOWS_CONSOLE;
  return {
    exitOnCtrlC: false,
    clearOnShutdown: !compatibilityMode,
    screenMode: compatibilityMode ? "main-screen" : "alternate-screen",
    consoleMode: "disabled",
    backgroundColor,
    targetFps: 30,
    ...(compatibilityMode
      ? {
        enableMouseMovement: false,
        useMouse: false,
        useKittyKeyboard: null,
      }
      : {}),
  };
}

function terminalCanRenderUnicode() {
  if (process.platform !== "win32") return true;
  if (hasModernWindowsTerminal()) return true;

  const codePage = spawnSync("chcp", {
    encoding: "utf8",
    shell: true,
    windowsHide: true,
  });
  const output = `${codePage.stdout || ""} ${codePage.stderr || ""}`;
  return /\b65001\b/.test(output);
}

function hasModernWindowsTerminal() {
  if (process.platform !== "win32") return true;
  return Boolean(
    process.env.WT_SESSION ||
    process.env.TERM_PROGRAM ||
    process.env.ConEmuANSI === "ON" ||
    process.env.ANSICON ||
    process.env.MSYSTEM
  );
}

function installSafeTerminalWrites() {
  if (!ASCII_MODE) return;
  patchTerminalWrite(process.stdout);
  patchTerminalWrite(process.stderr);
}

function patchTerminalWrite(stream) {
  if (!stream || stream.__robloxMcpAsciiPatched) return;
  const originalWrite = stream.write.bind(stream);
  stream.write = (chunk, encoding, callback) => {
    if (typeof encoding === "function") {
      callback = encoding;
      encoding = undefined;
    }
    if (typeof chunk === "string") {
      chunk = replaceUnsupportedTerminalCharacters(chunk);
    } else if (Buffer.isBuffer(chunk)) {
      chunk = Buffer.from(replaceUnsupportedTerminalCharacters(chunk.toString("utf8")), "utf8");
    }
    return originalWrite(chunk, encoding, callback);
  };
  Object.defineProperty(stream, "__robloxMcpAsciiPatched", {
    value: true,
    configurable: true,
  });
}

function replaceUnsupportedTerminalCharacters(value) {
  return String(value).replace(/[^\x00-\x7F]/g, "?");
}

function getArgValue(flag) {
  const index = process.argv.indexOf(flag);
  if (index === -1) return null;
  const value = process.argv[index + 1];
  return value && !value.startsWith("--") ? value : null;
}

function parseHarnessIds(value) {
  if (!value) return [];
  return [...new Set(String(value).split(",").map((id) => id.trim()).filter(Boolean))];
}

function normalizeServerName(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) return DEFAULT_SERVER_NAME;
  return trimmed;
}

function homePath(...parts) {
  return path.join(os.homedir(), ...parts);
}

function antigravityConfigPath() {
  if (process.platform === "win32") {
    return homePath(".gemini", "config", "mcp_config.json");
  }
  return homePath(".gemini", "antigravity", "mcp_config.json");
}

function traeConfigPath() {
  const appData =
    process.platform === "win32"
      ? process.env.APPDATA || homePath("AppData", "Roaming")
      : process.platform === "darwin"
        ? homePath("Library", "Application Support")
        : process.env.XDG_CONFIG_HOME || homePath(".config");
  return path.join(appData, "Trae", "User", "settings", "mcp.json");
}

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/") || value.startsWith("~\\")) return path.join(os.homedir(), value.slice(2));
  return value;
}

function shrinkHome(value) {
  const home = os.homedir();
  return String(value).startsWith(home) ? `~${String(value).slice(home.length)}` : String(value);
}

function readPackageVersion() {
  try {
    const packageJson = JSON.parse(fsSync.readFileSync(path.join(CURRENT_REPO_DIR, "package.json"), "utf8"));
    return typeof packageJson.version === "string" && packageJson.version ? packageJson.version : "1";
  } catch {
    return "1";
  }
}

function vscodeGlobalStoragePath(...parts) {
  const appData =
    process.platform === "win32"
      ? process.env.APPDATA || homePath("AppData", "Roaming")
      : process.platform === "darwin"
        ? homePath("Library", "Application Support")
        : process.env.XDG_CONFIG_HOME || homePath(".config");
  const codeRoot = process.platform === "darwin" ? path.join(appData, "Code") : path.join(appData, "Code");
  return path.join(codeRoot, "User", "globalStorage", ...parts);
}

function vscodeSettingsPath() {
  const appData =
    process.platform === "win32"
      ? process.env.APPDATA || homePath("AppData", "Roaming")
      : process.platform === "darwin"
        ? homePath("Library", "Application Support")
        : process.env.XDG_CONFIG_HOME || homePath(".config");
  return path.join(appData, "Code", "User", "settings.json");
}

// OpenCode resolves its global config through XDG paths on every platform, Windows included.
function opencodeConfigDir() {
  return path.join(process.env.XDG_CONFIG_HOME || homePath(".config"), "opencode");
}

function opencodeConfigPath() {
  if (process.env.OPENCODE_CONFIG) return expandHome(process.env.OPENCODE_CONFIG);
  const dir = opencodeConfigDir();
  const jsonPath = path.join(dir, "opencode.json");
  const jsoncPath = path.join(dir, "opencode.jsonc");
  // Writing opencode.json next to an existing opencode.jsonc would split the config in two.
  if (!fsSync.existsSync(jsonPath) && fsSync.existsSync(jsoncPath)) return jsoncPath;
  return jsonPath;
}

function gooseConfigPath() {
  if (process.platform === "win32") {
    return path.join(process.env.APPDATA || homePath("AppData", "Roaming"), "Block", "goose", "config", "config.yaml");
  }
  return homePath(".config", "goose", "config.yaml");
}

function claudeDesktopConfigPaths() {
  if (process.platform === "win32") {
    return uniquePaths([
      path.join(process.env.APPDATA || homePath("AppData", "Roaming"), "Claude", "claude_desktop_config.json"),
      path.join(process.env.LOCALAPPDATA || homePath("AppData", "Local"), "Packages", "Claude_pzs8sxrjxfjjc", "LocalCache", "Roaming", "Claude", "claude_desktop_config.json"),
    ]);
  }
  if (process.platform === "darwin") {
    return [homePath("Library", "Application Support", "Claude", "claude_desktop_config.json")];
  }
  return [homePath(".config", "Claude", "claude_desktop_config.json")];
}

function uniquePaths(paths) {
  return [...new Set(paths)];
}

function stripJsonComments(input) {
  return input
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");
}

function tomlString(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function yamlString(value) {
  return JSON.stringify(String(value));
}

function escapeRe(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function quote(value) {
  const s = String(value);
  return /\s/.test(s) ? JSON.stringify(s) : s;
}

function visibleLength(value) {
  return stripAnsi(value).length;
}

function padAnsi(value, width) {
  return value + " ".repeat(Math.max(0, width - visibleLength(value)));
}

function stripAnsi(value) {
  return String(value).replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");
}

function toggle(set, value) {
  if (set.has(value)) set.delete(value);
  else set.add(value);
}

function hideCursor() {
  if (ASCII_MODE) return;
  if (process.stdout.isTTY) process.stdout.write("\x1b[?25l");
}

function showCursor() {
  if (ASCII_MODE) return;
  if (process.stdout.isTTY) process.stdout.write("\x1b[?25h");
}

function enterAlternateScreen() {
  if (ASCII_MODE) return;
  if (process.stdout.isTTY) process.stdout.write("\x1b[?1049h\x1b[2J\x1b[H");
}

function leaveAlternateScreen() {
  if (ASCII_MODE) return;
  if (process.stdout.isTTY) process.stdout.write("\x1b[?1049l");
}
