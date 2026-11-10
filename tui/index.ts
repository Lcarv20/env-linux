#!/usr/bin/env bun
/**
 * env-linux OpenTUI Installer & Package Snake
 *
 * Terminal UI built with @opentui/core featuring:
 * - Live stage progress with animated spinner & status icons
 * - Real-time command action feed & bash event streaming
 * - Interactive button prompts (Plan confirmation, Mode selection, Guided step-by-step)
 * - 🐍 Package Snake & Dependency Dodge game:
 *     * Food pellets named after real manifest packages (+10 pts)
 *     * Golden Boost pellets on bash step/cmd completion (+50 pts)
 *     * Cursed Conflict pellets (✖ dankcalendar) (-20 pts)
 *     * Persistent high score tracking
 */

import {
  createCliRenderer,
  BoxRenderable,
  FrameBufferRenderable,
  RGBA,
  type CliRenderer,
} from "@opentui/core";
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

// ------------------------------------------------------------- Configuration & CLI
const REPO_ROOT = path.resolve(__dirname, "..");
const MANIFEST_DIR = path.join(REPO_ROOT, "manifest");
const STAGES_DIR = path.join(REPO_ROOT, "stages");
const LOG_FILE = path.join(REPO_ROOT, "setup.log");
const HIGH_SCORE_FILE = path.join(
  os.homedir(),
  ".local/state/env-linux/snake-highscore.json"
);

// CLI Arguments parsing
const argv = process.argv.slice(2);
let isDryRun = false;
let isYes = false;
let isDemo = false;
let hostFlag = "auto";
let withExtras = false;
let withMango = false;
let profile = "custom";

for (const arg of argv) {
  if (arg === "--dry-run") isDryRun = true;
  else if (arg === "-y" || arg === "--yes") isYes = true;
  else if (arg === "--demo") {
    isDemo = true;
    isDryRun = true;
  } else if (arg.startsWith("--host=")) hostFlag = arg.slice(7);
  else if (arg === "--with-extras") withExtras = true;
  else if (arg === "--with-mango") withMango = true;
  else if (arg.startsWith("--profile=")) profile = arg.slice(10);
}

// ---------------------------------------------------------------- Hardware Profile
function detectProduct(): string {
  try {
    if (fs.existsSync("/sys/devices/virtual/dmi/id/product_name")) {
      return fs.readFileSync("/sys/devices/virtual/dmi/id/product_name", "utf-8").trim();
    }
  } catch {}
  return "Linux";
}

function detectVirt(): string {
  try {
    const res = spawnSync("systemd-detect-virt", { encoding: "utf-8" });
    const out = (res.stdout || "").trim();
    return out && out !== "none" ? out : "";
  } catch {}
  return "";
}

function detectHostProfile(product: string, virt: string): string {
  if (product === "iMac18,3") return "imac18-3";
  if (["qemu", "kvm", "vmware", "bochs", "microsoft", "xen"].includes(virt)) return "vm";
  return "none";
}

const dmiProduct = detectProduct();
const virtType = detectVirt();
const detectedHost = detectHostProfile(dmiProduct, virtType);
const hostProfile = hostFlag === "auto" ? detectedHost : hostFlag;

// -------------------------------------------------------------------- High Scores
function loadHighScore(): number {
  try {
    if (fs.existsSync(HIGH_SCORE_FILE)) {
      const data = JSON.parse(fs.readFileSync(HIGH_SCORE_FILE, "utf-8"));
      return typeof data.highScore === "number" ? data.highScore : 0;
    }
  } catch {}
  return 0;
}

function saveHighScore(score: number): void {
  try {
    fs.mkdirSync(path.dirname(HIGH_SCORE_FILE), { recursive: true });
    fs.writeFileSync(
      HIGH_SCORE_FILE,
      JSON.stringify({ highScore: score, date: new Date().toISOString() }, null, 2),
      "utf-8"
    );
  } catch {}
}

let highScore = loadHighScore();

// ----------------------------------------------------------------- Package Pool
function loadManifestPackages(): string[] {
  const pkgs: string[] = [];
  const files = [
    "dnf-core.txt",
    "mise-core.txt",
    "plugins.txt",
    "dnf-extras.txt",
    "mise-extras.txt",
  ];
  for (const f of files) {
    const p = path.join(MANIFEST_DIR, f);
    if (fs.existsSync(p)) {
      const lines = fs.readFileSync(p, "utf-8").split("\n");
      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed && !trimmed.startsWith("#")) {
          const name = trimmed.split(/\s+/)[0];
          if (name && !pkgs.includes(name)) pkgs.push(name);
        }
      }
    }
  }
  return pkgs.length > 0
    ? pkgs
    : ["pipewire", "niri", "dms", "kitty", "zsh", "wireplumber", "waybar", "swaylock", "alacritty"];
}

const packagePool = loadManifestPackages();
let packageIndex = 0;
function getNextPackage(): string {
  const pkg = packagePool[packageIndex % packagePool.length];
  packageIndex++;
  return pkg;
}

// ---------------------------------------------------------------- Stages Definition
interface StageItem {
  file: string;
  num: string;
  title: string;
  desc: string;
  status: "pending" | "running" | "ok" | "skipped" | "failed";
}

const ALL_STAGES_DEF: Array<{ file: string; num: string; title: string; desc: string }> = [
  { file: "00-repos.sh", num: "00", title: "Repositories", desc: "RPM Fusion, Terra, COPRs" },
  { file: "10-desktop-base.sh", num: "10", title: "Desktop base", desc: "PipeWire, portals, fonts, mise CLI, zsh" },
  { file: "20-niri-dms.sh", num: "20", title: "Niri + Dux check", desc: "Verify niri / dms / greeter binaries" },
  { file: "30-assets.sh", num: "30", title: "Assets", desc: "Wallpapers, fonts, JuxCursor, dfiles-shell" },
  { file: "35-plugins.sh", num: "35", title: "DMS plugins", desc: "Restore registry plugins, link custom repos" },
  { file: "40-dotfiles.sh", num: "40", title: "Dotfiles", desc: "Stow niri, dms, portals, environment.d" },
  { file: "45-own-software.sh", num: "45", title: "Own software", desc: "web-app-installer (websites → apps)" },
  { file: "50-services.sh", num: "50", title: "Services", desc: "greetd + dms-greeter, user systemd units" },
  { file: "60-extras.sh", num: "60", title: "Extras", desc: "clang, mise runtimes, Keychron udev rule" },
  { file: "90-hardware.sh", num: "90", title: "Hardware quirks", desc: "iMac 5K / VM guest agents" },
];

const stages: StageItem[] = [];
for (const s of ALL_STAGES_DEF) {
  if (s.file === "60-extras.sh" && !withExtras) continue;
  if (fs.existsSync(path.join(STAGES_DIR, s.file))) {
    stages.push({ ...s, status: "pending" });
  }
}

// ---------------------------------------------------------------- Visual Theme
const C_BG = RGBA.fromHex("#0d1117");
const C_PANEL_BG = RGBA.fromHex("#161b22");
const C_HUD_BG = RGBA.fromHex("#1c2128");
const C_BORDER = RGBA.fromHex("#30363d");
const C_BORDER_MAGENTA = RGBA.fromHex("#bc8cff");
const C_BORDER_GREEN = RGBA.fromHex("#238636");
const C_BORDER_GOLD = RGBA.fromHex("#d29922");
const C_BORDER_RED = RGBA.fromHex("#da3633");

const C_TEXT = RGBA.fromHex("#c9d1d9");
const C_TEXT_MUTED = RGBA.fromHex("#6e7681");
const C_TEXT_WHITE = RGBA.fromHex("#ffffff");
const C_GREEN = RGBA.fromHex("#3fb950");
const C_BRIGHT_GREEN = RGBA.fromHex("#56d364");
const C_MAGENTA = RGBA.fromHex("#bc8cff");
const C_CYAN = RGBA.fromHex("#58a6ff");
const C_GOLD = RGBA.fromHex("#d29922");
const C_YELLOW = RGBA.fromHex("#e3b341");
const C_RED = RGBA.fromHex("#f85149");

// ---------------------------------------------------------------- Snake Engine
interface Point {
  x: number;
  y: number;
}

interface GoldenPellet extends Point {
  expires: number;
}

interface CursedPellet extends Point {
  label: string;
  expires: number;
}

class SnakeGame {
  width: number = 44;
  height: number = 8;
  playTop: number = 2; // Rows 0 & 1 reserved for HUD

  snake: Point[] = [];
  dir: Point = { x: 1, y: 0 };
  nextDir: Point = { x: 1, y: 0 };
  score: number = 0;
  isArcade: boolean = false;
  isPaused: boolean = false;

  currentFoodPkg: string = getNextPackage();
  food: Point = { x: 10, y: 4 };
  goldenPellet: GoldenPellet | null = null;
  cursedPellet: CursedPellet | null = null;

  statusMessage: string = "Press [P] for Arcade mode · WASD/Arrows to play!";
  statusColor: RGBA = C_YELLOW;
  statusExpires: number = Date.now() + 6000;

  constructor() {
    this.reset();
  }

  reset(): void {
    const startY = Math.max(this.playTop, Math.floor(this.height / 2));
    this.snake = [
      { x: 8, y: startY },
      { x: 7, y: startY },
      { x: 6, y: startY },
    ];
    this.dir = { x: 1, y: 0 };
    this.nextDir = { x: 1, y: 0 };
    this.spawnFood();
  }

  resize(w: number, h: number): void {
    this.width = Math.max(20, w);
    this.height = Math.max(6, h);
    // keep within boundaries
    for (const p of this.snake) {
      p.x = Math.max(0, Math.min(this.width - 1, p.x));
      p.y = Math.max(this.playTop, Math.min(this.height - 1, p.y));
    }
  }

  setStatus(msg: string, color: RGBA, durationMs: number = 3000): void {
    this.statusMessage = msg;
    this.statusColor = color;
    this.statusExpires = Date.now() + durationMs;
  }

  spawnFood(): void {
    const playH = Math.max(1, this.height - this.playTop);
    let attempts = 0;
    while (attempts < 50) {
      attempts++;
      const rx = Math.floor(Math.random() * (this.width - 2)) + 1;
      const ry = Math.floor(Math.random() * playH) + this.playTop;
      if (!this.snake.some((s) => s.x === rx && s.y === ry)) {
        this.food = { x: rx, y: ry };
        return;
      }
    }
  }

  spawnGoldenPellet(): void {
    const playH = Math.max(1, this.height - this.playTop);
    const rx = Math.floor(Math.random() * (this.width - 2)) + 1;
    const ry = Math.floor(Math.random() * playH) + this.playTop;
    this.goldenPellet = {
      x: rx,
      y: ry,
      expires: Date.now() + 10000, // 10s lifetime
    };
    this.setStatus("★ Golden Boost Pellet spawned (+50 pts)!", C_GOLD, 3000);
  }

  spawnCursedPellet(): void {
    if (this.cursedPellet && Date.now() < this.cursedPellet.expires) return;
    const playH = Math.max(1, this.height - this.playTop);
    const rx = Math.floor(Math.random() * (this.width - 12)) + 2;
    const ry = Math.floor(Math.random() * playH) + this.playTop;
    this.cursedPellet = {
      x: rx,
      y: ry,
      label: "dankcalendar",
      expires: Date.now() + 8000, // 8s lifetime
    };
    this.setStatus("⚠ Conflict Pellet appeared: ✖ dankcalendar!", C_RED, 3000);
  }

  changeDir(newDir: Point): void {
    // Prevent 180-degree instant turn into self
    if (newDir.x !== 0 && this.dir.x !== 0) return;
    if (newDir.y !== 0 && this.dir.y !== 0) return;
    this.nextDir = newDir;
  }

  tick(isStageRunning: boolean): void {
    const active = isStageRunning || this.isArcade;
    if (!active || this.isPaused) return;

    // Apply direction
    this.dir = this.nextDir;
    const head = { ...this.snake[0] };
    head.x += this.dir.x;
    head.y += this.dir.y;

    // Wrap around boundaries
    if (head.x < 0) head.x = this.width - 1;
    if (head.x >= this.width) head.x = 0;
    if (head.y < this.playTop) head.y = this.height - 1;
    if (head.y >= this.height) head.y = this.playTop;

    // Check collision with self
    const hitSelf = this.snake.some((s) => s.x === head.x && s.y === head.y);
    if (hitSelf) {
      this.setStatus("Bounced into tail! Snake refreshed.", C_YELLOW, 2500);
      this.snake = this.snake.slice(0, 3);
      return;
    }

    // Move snake
    this.snake.unshift(head);

    // Check collision with normal Food
    if (head.x === this.food.x && head.y === this.food.y) {
      this.score += 10;
      if (this.score > highScore) {
        highScore = this.score;
        saveHighScore(highScore);
      }
      const ate = this.currentFoodPkg;
      this.currentFoodPkg = getNextPackage();
      this.setStatus(`Ate ${ate}! (+10 pts)`, C_BRIGHT_GREEN, 2500);
      this.spawnFood();
    }
    // Check collision with Golden Boost Pellet
    else if (
      this.goldenPellet &&
      Date.now() < this.goldenPellet.expires &&
      head.x === this.goldenPellet.x &&
      head.y === this.goldenPellet.y
    ) {
      this.score += 50;
      if (this.score > highScore) {
        highScore = this.score;
        saveHighScore(highScore);
      }
      this.goldenPellet = null;
      this.setStatus("★ BASH BOOST! Installed package synced (+50 pts)!", C_GOLD, 3500);
    }
    // Check collision with Cursed Conflict Pellet
    else if (
      this.cursedPellet &&
      Date.now() < this.cursedPellet.expires &&
      head.x >= this.cursedPellet.x &&
      head.x <= this.cursedPellet.x + 2 &&
      head.y === this.cursedPellet.y
    ) {
      this.score = Math.max(0, this.score - 20);
      this.snake = this.snake.slice(0, Math.max(3, this.snake.length - 2));
      this.cursedPellet = null;
      this.setStatus("RPM file conflict on /usr/bin/dcal! (-20 pts)", C_RED, 4000);
      this.snake.pop(); // reduce length
    } else {
      this.snake.pop();
    }

    // Expire pellets
    if (this.goldenPellet && Date.now() > this.goldenPellet.expires) {
      this.goldenPellet = null;
    }
    if (this.cursedPellet && Date.now() > this.cursedPellet.expires) {
      this.cursedPellet = null;
    }

    // Occasional conflict pellet spawn (~1 in 150 ticks = ~10-15s)
    if (!this.cursedPellet && Math.random() < 0.007) {
      this.spawnCursedPellet();
    }
  }

  render(fb: FrameBufferRenderable): void {
    const buf = fb.frameBuffer;
    buf.clear(C_BG);

    // Row 0: HUD Bar
    buf.fillRect(0, 0, this.width, 1, C_HUD_BG);
    const scoreStr = `Score: ${this.score}`;
    const lenStr = `Len: ${this.snake.length}`;
    const nextPkgStr = `Next pkg: ${this.currentFoodPkg} (+10)`;
    const modeStr = this.isArcade ? "ARCADE MODE" : "PLAYING";

    buf.drawText(scoreStr, 1, 0, C_GOLD);
    buf.drawText(lenStr, 13, 0, C_TEXT_WHITE);
    buf.drawText(nextPkgStr, 22, 0, C_BRIGHT_GREEN);
    const rightOffset = Math.max(this.width - modeStr.length - 1, 45);
    buf.drawText(modeStr, rightOffset, 0, C_CYAN);

    // Row 1: Status Flash or Controls Guide
    if (Date.now() < this.statusExpires) {
      buf.drawText(this.statusMessage, 1, 1, this.statusColor);
    } else {
      buf.drawText(
        "WASD: Steer · P: Toggle Arcade · ★ Golden Bash Boost (+50)",
        1,
        1,
        C_TEXT_MUTED
      );
    }

    // Draw Cursed Pellet
    if (this.cursedPellet && Date.now() < this.cursedPellet.expires) {
      buf.drawText(`✖ ${this.cursedPellet.label}`, this.cursedPellet.x, this.cursedPellet.y, C_RED);
    }

    // Draw Golden Boost Pellet
    if (this.goldenPellet && Date.now() < this.goldenPellet.expires) {
      buf.drawText("★", this.goldenPellet.x, this.goldenPellet.y, C_GOLD);
    }

    // Draw Normal Food Pellet
    buf.drawText("●", this.food.x, this.food.y, C_BRIGHT_GREEN);

    // Draw Snake Body
    for (let i = 1; i < this.snake.length; i++) {
      const p = this.snake[i];
      buf.drawText("■", p.x, p.y, C_GREEN);
    }
    // Draw Snake Head
    if (this.snake.length > 0) {
      const head = this.snake[0];
      buf.drawText("◆", head.x, head.y, C_BRIGHT_GREEN);
    }
  }
}

// ---------------------------------------------------------------- UI State & Prompts
interface PromptOption {
  key: string;
  label: string;
  isDefault?: boolean;
}

interface ActivePrompt {
  title: string;
  options: PromptOption[];
  selectedIndex: number;
  resolve: (choice: string) => void;
}

const SPINNER_CHARS = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

class OpenTuiInstaller {
  renderer!: CliRenderer;
  snake: SnakeGame = new SnakeGame();

  // Renderables
  headerBox!: BoxRenderable;
  headerFB!: FrameBufferRenderable;

  bodyBox!: BoxRenderable;

  leftBox!: BoxRenderable;
  leftFB!: FrameBufferRenderable;

  rightCol!: BoxRenderable;
  logBox!: BoxRenderable;
  logFB!: FrameBufferRenderable;
  snakeBox!: BoxRenderable;
  snakeFB!: FrameBufferRenderable;

  // Runtime State
  currentStageIdx: number = 0;
  activeCommand: string = "";
  logFeed: Array<{ text: string; color: RGBA }> = [];
  spinnerIndex: number = 0;
  activePrompt: ActivePrompt | null = null;
  stageRunning: boolean = false;
  finished: boolean = false;
  failedCount: number = 0;
  okCount: number = 0;
  skippedCount: number = 0;

  modeName: string = isDemo ? "DEMO" : isDryRun ? "DRY-RUN" : isYes ? "AUTO" : "GUIDED";

  async init(): Promise<void> {
    this.renderer = await createCliRenderer({
      exitOnCtrlC: true,
      useMouse: false,
    });

    const termW = this.renderer.width || 80;
    const termH = this.renderer.height || 24;

    this.setupLayout(termW, termH);
    this.setupInput();

    // Redraw loop (~16 fps / 60ms)
    setInterval(() => {
      this.tick();
    }, 60);

    this.renderer.on("resize", (dim: { width: number; height: number }) => {
      this.handleResize(dim.width, dim.height);
    });
  }

  setupLayout(width: number, height: number): void {
    const root = this.renderer.root;
    for (const child of [...root.getChildren()]) {
      root.remove(child);
    }

    const headerHeight = 3;
    const bodyHeight = Math.max(12, height - headerHeight);
    const leftWidth = Math.min(34, Math.floor(width * 0.36));
    const rightWidth = Math.max(30, width - leftWidth);

    const logHeight = Math.max(8, Math.floor(bodyHeight * 0.52));
    const snakeHeight = Math.max(7, bodyHeight - logHeight);

    // Header Box
    this.headerBox = new BoxRenderable(this.renderer, {
      width,
      height: headerHeight,
      borderStyle: "single",
      borderColor: C_BORDER_MAGENTA,
      title: "╭─ env-linux · Fedora → Niri + Dux Shell ─╮",
    });
    this.headerFB = new FrameBufferRenderable(this.renderer, {
      width: Math.max(20, width - 2),
      height: 1,
    });
    this.headerBox.add(this.headerFB);

    // Body Container
    this.bodyBox = new BoxRenderable(this.renderer, {
      flexDirection: "row",
      width,
      height: bodyHeight,
    });

    // Left Panel (Stages)
    this.leftBox = new BoxRenderable(this.renderer, {
      width: leftWidth,
      height: bodyHeight,
      borderStyle: "single",
      borderColor: C_BORDER,
      title: "Stages",
    });
    this.leftFB = new FrameBufferRenderable(this.renderer, {
      width: Math.max(10, leftWidth - 2),
      height: Math.max(4, bodyHeight - 2),
    });
    this.leftBox.add(this.leftFB);

    // Right Column
    this.rightCol = new BoxRenderable(this.renderer, {
      flexDirection: "column",
      width: rightWidth,
      height: bodyHeight,
    });

    // Right Top (Log & Action)
    this.logBox = new BoxRenderable(this.renderer, {
      width: rightWidth,
      height: logHeight,
      borderStyle: "single",
      borderColor: C_BORDER,
      title: "Stage & Action Log",
    });
    this.logFB = new FrameBufferRenderable(this.renderer, {
      width: Math.max(10, rightWidth - 2),
      height: Math.max(4, logHeight - 2),
    });
    this.logBox.add(this.logFB);

    // Right Bottom (Snake)
    this.snakeBox = new BoxRenderable(this.renderer, {
      width: rightWidth,
      height: snakeHeight,
      borderStyle: "single",
      borderColor: C_BORDER_GREEN,
      title: "🐍 PACKAGE SNAKE",
      bottomTitle: "WASD: Steer · P: Arcade",
      bottomTitleAlignment: "right",
    });
    this.snakeFB = new FrameBufferRenderable(this.renderer, {
      width: Math.max(10, rightWidth - 2),
      height: Math.max(4, snakeHeight - 2),
    });
    this.snake.resize(this.snakeFB.width, this.snakeFB.height);
    this.snakeBox.add(this.snakeFB);

    this.rightCol.add(this.logBox);
    this.rightCol.add(this.snakeBox);

    this.bodyBox.add(this.leftBox);
    this.bodyBox.add(this.rightCol);

    root.add(this.headerBox);
    root.add(this.bodyBox);
  }

  handleResize(width: number, height: number): void {
    this.setupLayout(width, height);
  }

  setupInput(): void {
    this.renderer.keyInput.on("keypress", (event) => {
      const name = (event.name || "").toLowerCase();

      // Ctrl+C handling
      if (name === "c" && event.ctrl) {
        this.destroyAndExit(0);
        return;
      }

      // Snake Steer (WASD works ANYTIME, even during button prompts!)
      if (name === "w") this.snake.changeDir({ x: 0, y: -1 });
      else if (name === "s") this.snake.changeDir({ x: 0, y: 1 });
      else if (name === "a") this.snake.changeDir({ x: -1, y: 0 });
      else if (name === "d") this.snake.changeDir({ x: 1, y: 0 });

      // Toggle Arcade mode
      if (name === "p") {
        this.snake.isArcade = !this.snake.isArcade;
        this.snake.setStatus(
          this.snake.isArcade ? "Arcade Mode ACTIVE! WASD to steer." : "Arcade Mode PAUSED.",
          C_CYAN,
          3000
        );
        return;
      }

      // Arrow keys: if active prompt exists, left/right navigate buttons; up/down steer snake
      if (this.activePrompt) {
        if (name === "left" || name === "h") {
          this.activePrompt.selectedIndex =
            (this.activePrompt.selectedIndex - 1 + this.activePrompt.options.length) %
            this.activePrompt.options.length;
          return;
        } else if (name === "right" || name === "l" || name === "tab") {
          this.activePrompt.selectedIndex =
            (this.activePrompt.selectedIndex + 1) % this.activePrompt.options.length;
          return;
        } else if (name === "enter" || name === "space") {
          const choice = this.activePrompt.options[this.activePrompt.selectedIndex].key;
          const resolve = this.activePrompt.resolve;
          this.activePrompt = null;
          resolve(choice);
          return;
        }

        // Hotkeys for options
        for (const opt of this.activePrompt.options) {
          if (name === opt.key.toLowerCase() || name === opt.label.charAt(0).toLowerCase()) {
            const resolve = this.activePrompt.resolve;
            this.activePrompt = null;
            resolve(opt.key);
            return;
          }
        }
      } else {
        // Arrow keys steer snake when no prompt is capturing horizontal arrows
        if (name === "up") this.snake.changeDir({ x: 0, y: -1 });
        else if (name === "down") this.snake.changeDir({ x: 0, y: 1 });
        else if (name === "left") this.snake.changeDir({ x: -1, y: 0 });
        else if (name === "right") this.snake.changeDir({ x: 1, y: 0 });
      }
    });
  }

  prompt(title: string, options: PromptOption[]): Promise<string> {
    return new Promise((resolve) => {
      this.activePrompt = {
        title,
        options,
        selectedIndex: 0,
        resolve,
      };
    });
  }

  addLog(msg: string, color: RGBA = C_TEXT): void {
    this.logFeed.push({ text: msg, color });
    if (this.logFeed.length > 50) this.logFeed.shift();
  }

  tick(): void {
    this.spinnerIndex = (this.spinnerIndex + 1) % SPINNER_CHARS.length;

    // Tick Snake
    this.snake.tick(this.stageRunning);

    // Render Panels
    this.renderHeader();
    this.renderStages();
    this.renderLogPanel();
    this.renderSnake();

    this.renderer.requestAnimationFrame(() => {});
  }

  renderHeader(): void {
    const buf = this.headerFB.frameBuffer;
    buf.clear(C_PANEL_BG);

    const w = this.headerFB.width;
    const virtStr = virtType ? ` (virt: ${virtType})` : "";
    const info = `Machine: ${dmiProduct}${virtStr} · host: ${hostProfile}`;
    const badge = `[${this.modeName}]`;
    const scoreStr = `🏆 Snake High Score: ${highScore}`;

    buf.drawText(info, 1, 0, C_CYAN);
    const badgeX = Math.floor(w / 2) - Math.floor(badge.length / 2);
    buf.drawText(badge, Math.max(info.length + 3, badgeX), 0, C_MAGENTA);

    const scoreX = Math.max(w - scoreStr.length - 1, 55);
    buf.drawText(scoreStr, scoreX, 0, C_GOLD);
  }

  renderStages(): void {
    const buf = this.leftFB.frameBuffer;
    buf.clear(C_BG);

    const spin = SPINNER_CHARS[this.spinnerIndex];
    let y = 1;

    for (let i = 0; i < stages.length; i++) {
      if (y >= this.leftFB.height) break;
      const s = stages[i];
      let icon = "○";
      let iconColor = C_TEXT_MUTED;
      let titleColor = C_TEXT;

      if (s.status === "ok") {
        icon = "✔";
        iconColor = C_GREEN;
        titleColor = C_TEXT;
      } else if (s.status === "running") {
        icon = spin;
        iconColor = C_MAGENTA;
        titleColor = C_TEXT_WHITE;
      } else if (s.status === "skipped") {
        icon = "↷";
        iconColor = C_YELLOW;
        titleColor = C_TEXT_MUTED;
      } else if (s.status === "failed") {
        icon = "✖";
        iconColor = C_RED;
        titleColor = C_RED;
      }

      buf.drawText(icon, 1, y, iconColor);
      const label = `${s.num} ${s.title}`;
      buf.drawText(label.slice(0, this.leftFB.width - 5), 4, y, titleColor);

      y += 2;
    }
  }

  renderLogPanel(): void {
    const buf = this.logFB.frameBuffer;
    buf.clear(C_BG);

    const w = this.logFB.width;
    let y = 0;

    // Current stage or summary header
    if (this.finished) {
      const summaryTitle =
        this.failedCount > 0 ? "Installation Finished with Failures" : "Installation Complete!";
      const summaryColor = this.failedCount > 0 ? C_RED : C_GREEN;
      buf.drawText(summaryTitle, 1, y++, summaryColor);
      buf.drawText(
        `Results: ${this.okCount} OK · ${this.skippedCount} Skipped · ${this.failedCount} Failed`,
        1,
        y++,
        C_TEXT
      );
      buf.drawText(`Log written to: ${LOG_FILE}`, 1, y++, C_TEXT_MUTED);
    } else {
      const current = stages[this.currentStageIdx] || stages[0];
      const stageHeader = `Stage [${this.currentStageIdx + 1}/${stages.length}] · ${current.title}`;
      buf.drawText(stageHeader, 1, y++, C_CYAN);
      buf.drawText(current.desc.slice(0, w - 2), 1, y++, C_TEXT_MUTED);
    }

    // Active command spinner
    if (this.activeCommand) {
      const spin = SPINNER_CHARS[this.spinnerIndex];
      const cmdText = `${spin} ${this.activeCommand}`;
      buf.drawText(cmdText.slice(0, w - 2), 1, y++, C_YELLOW);
    } else {
      y++;
    }

    // Interactive Button Bar (if prompt active)
    if (this.activePrompt) {
      buf.drawText(this.activePrompt.title, 1, y++, C_TEXT_WHITE);
      let btnX = 1;
      for (let i = 0; i < this.activePrompt.options.length; i++) {
        const opt = this.activePrompt.options[i];
        const isSelected = i === this.activePrompt.selectedIndex;
        const btnStr = `[ ${opt.label} ]`;

        if (isSelected) {
          buf.fillRect(btnX, y, btnStr.length, 1, C_MAGENTA);
          buf.drawText(btnStr, btnX, y, C_TEXT_WHITE);
        } else {
          buf.fillRect(btnX, y, btnStr.length, 1, C_HUD_BG);
          buf.drawText(btnStr, btnX, y, C_TEXT);
        }
        btnX += btnStr.length + 2;
      }
      y += 2;
    }

    // Divider
    buf.fillRect(1, y++, w - 2, 1, C_BORDER);

    // Scrollable Feed of steps
    const maxFeedLines = Math.max(1, this.logFB.height - y);
    const visibleFeed = this.logFeed.slice(-maxFeedLines);
    for (const item of visibleFeed) {
      if (y >= this.logFB.height) break;
      buf.drawText(item.text.slice(0, w - 2), 1, y++, item.color);
    }
  }

  renderSnake(): void {
    this.snake.render(this.snakeFB);
  }

  async runStage(stage: StageItem): Promise<boolean> {
    this.stageRunning = true;
    stage.status = "running";
    this.activeCommand = `Starting ${stage.title}...`;

    const stageScriptPath = path.join(STAGES_DIR, stage.file);

    const childEnv: Record<string, string> = {
      ...(process.env as Record<string, string>),
      DOTS_ROOT: REPO_ROOT,
      ENV_TUI: "1",
      ENV_TUI_DEMO: isDemo ? "1" : "0",
      DRY_RUN: isDryRun ? "true" : "false",
      HOST_PROFILE: hostProfile,
      WITH_EXTRAS: withExtras ? "true" : "false",
      WITH_MANGO: withMango ? "true" : "false",
      PROFILE: profile,
      ASSUME_YES: isYes ? "true" : "false",
      LOG_FILE: LOG_FILE,
      ENV_INSTALL_NESTED: "1",
    };

    return new Promise((resolve) => {
      const proc = spawn("bash", [stageScriptPath], {
        env: childEnv,
        stdio: ["ignore", "pipe", "pipe"],
      });

      let stdoutRemainder = "";
      proc.stdout.on("data", (chunk: Buffer) => {
        stdoutRemainder += chunk.toString("utf-8");
        const lines = stdoutRemainder.split("\n");
        stdoutRemainder = lines.pop() || "";

        for (const line of lines) {
          if (line.startsWith("@@ENV_TUI@@")) {
            try {
              const ev = JSON.parse(line.slice(11));
              this.handleTuiEvent(ev);
            } catch {}
          } else if (line.trim()) {
            this.addLog(line.trim(), C_TEXT_MUTED);
          }
        }
      });

      proc.stderr.on("data", (chunk: Buffer) => {
        const str = chunk.toString("utf-8").trim();
        if (str) {
          this.addLog(str, C_RED);
        }
      });

      proc.on("close", (code: number) => {
        this.stageRunning = false;
        this.activeCommand = "";
        if (code === 0) {
          stage.status = "ok";
          this.okCount++;
          this.snake.spawnGoldenPellet();
          this.addLog(`✔ ${stage.title} completed`, C_GREEN);
          resolve(true);
        } else {
          stage.status = "failed";
          this.failedCount++;
          this.addLog(`✖ ${stage.title} failed (exit code ${code})`, C_RED);
          resolve(false);
        }
      });
    });
  }

  handleTuiEvent(ev: any): void {
    switch (ev.event) {
      case "header":
        this.addLog(`── ${ev.title} ──`, C_MAGENTA);
        break;
      case "step":
        this.addLog(`✔ ${ev.message}`, C_GREEN);
        this.snake.spawnGoldenPellet();
        break;
      case "info":
        this.addLog(`• ${ev.message}`, C_CYAN);
        break;
      case "warn":
        this.addLog(`⚠ ${ev.message}`, C_YELLOW);
        break;
      case "error":
        this.addLog(`✖ ${ev.message}`, C_RED);
        break;
      case "dry":
        this.addLog(`[dry-run] ${ev.message}`, C_YELLOW);
        break;
      case "cmd_start":
        this.activeCommand = ev.description || ev.command || "Executing...";
        break;
      case "cmd_end":
        this.activeCommand = "";
        this.snake.spawnGoldenPellet();
        break;
    }
  }

  async run(): Promise<void> {
    await this.init();

    // 1. Initial Plan Confirmation (if not --yes)
    if (!isYes) {
      const planMsg = `Ready to install env-linux (${stages.length} stages)`;
      const choice = await this.prompt(planMsg, [
        { key: "run", label: "Run Plan" },
        { key: "mode", label: "Change Mode" },
        { key: "quit", label: "Quit" },
      ]);

      if (choice === "quit") {
        this.addLog("Installation cancelled by user.", C_YELLOW);
        this.destroyAndExit(0);
        return;
      }

      if (choice === "mode") {
        const modeChoice = await this.prompt("Select execution mode:", [
          { key: "guided", label: "Guided (confirm each stage)" },
          { key: "auto", label: "Automatic (run all stages)" },
        ]);
        if (modeChoice === "auto") {
          isYes = true;
          this.modeName = isDemo ? "DEMO" : isDryRun ? "DRY-RUN" : "AUTO";
        } else {
          this.modeName = "GUIDED";
        }
      }
    }

    // 2. Stages Execution Loop
    for (let i = 0; i < stages.length; i++) {
      this.currentStageIdx = i;
      const stage = stages[i];

      // If Guided mode: prompt user for this stage
      if (!isYes) {
        const promptMsg = `Ready: ${stage.num} · ${stage.title}`;
        const choice = await this.prompt(promptMsg, [
          { key: "run", label: "Run" },
          { key: "skip", label: "Skip" },
          { key: "quit", label: "Quit" },
        ]);

        if (choice === "skip") {
          stage.status = "skipped";
          this.skippedCount++;
          this.addLog(`↷ ${stage.title} skipped`, C_YELLOW);
          continue;
        } else if (choice === "quit") {
          this.addLog(`Installation stopped before ${stage.title}.`, C_YELLOW);
          break;
        }
      }

      const ok = await this.runStage(stage);
      if (!ok && !isYes) {
        const cont = await this.prompt(`${stage.title} failed. Continue?`, [
          { key: "yes", label: "Continue" },
          { key: "no", label: "Stop" },
        ]);
        if (cont === "no") break;
      }
    }

    // 3. Finished Summary
    this.finished = true;
    this.stageRunning = false;
    this.activeCommand = "";

    const finishChoice = await this.prompt("Installation finished.", [
      { key: "exit", label: "Exit (Enter)" },
      { key: "arcade", label: "Keep Playing Snake (P)" },
    ]);

    if (finishChoice === "arcade") {
      this.snake.isArcade = true;
      this.snake.setStatus("Arcade Mode! Press Ctrl+C or Q to exit anytime.", C_CYAN, 5000);
      // Wait for user to exit with Ctrl+C or Q
      await new Promise(() => {});
    } else {
      this.destroyAndExit(this.failedCount > 0 ? 1 : 0);
    }
  }

  destroyAndExit(code: number): void {
    try {
      this.renderer.destroy();
    } catch {}
    process.exit(code);
  }
}

// ---------------------------------------------------------------- Main Entry
const app = new OpenTuiInstaller();
app.run().catch((err) => {
  fs.writeFileSync("/tmp/tui-debug.log", String(err && err.stack ? err.stack : err));
  console.error("OpenTUI Installer Error:", err);
  process.exit(1);
});
