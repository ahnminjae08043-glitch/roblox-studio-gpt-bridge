import http from "node:http";
import { createHash, randomBytes, randomInt, randomUUID, timingSafeEqual } from "node:crypto";
import {
  claimCommands,
  cleanupMemory,
  countQueuedCommands,
  consumeRateLimit,
  deleteDevice,
  getCommand,
  getDevice,
  getHistory,
  getRateLimitStatus,
  memoryStats,
  recordHistory,
  rejectQueuedCommands,
  reserveDedupe,
  saveCommand,
  saveDevice,
  savePairing,
  takePairing,
  usesRedis
} from "./store.mjs";

const port = Number.parseInt(process.env.PORT ?? "8787", 10);
const apiKey = process.env.BRIDGE_API_KEY ?? "";
const publicBaseUrl = (
  process.env.PUBLIC_BASE_URL
  ?? (process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : "https://YOUR-DOMAIN.example.com")
).replace(/\/+$/, "");
const commandTtlMs = Number.parseInt(process.env.COMMAND_TTL_MS ?? "600000", 10);
const pairingTtlMs = Number.parseInt(process.env.PAIRING_TTL_MS ?? "600000", 10);
const deviceCommandLimit = Number.parseInt(process.env.DEVICE_COMMAND_LIMIT ?? "60", 10);
const deviceCommandWindowSeconds = Number.parseInt(
  process.env.DEVICE_COMMAND_WINDOW_SECONDS ?? "600",
  10
);
const dailyCommandLimit = Number.parseInt(process.env.DAILY_COMMAND_LIMIT ?? "300", 10);
const maxDeviceQueue = Number.parseInt(process.env.MAX_DEVICE_QUEUE ?? "20", 10);
const globalCommandLimit = Number.parseInt(process.env.GLOBAL_COMMAND_LIMIT ?? "1000", 10);
const globalCommandWindowSeconds = Number.parseInt(
  process.env.GLOBAL_COMMAND_WINDOW_SECONDS ?? "60",
  10
);
const maxRequestBytes = Number.parseInt(process.env.MAX_REQUEST_BYTES ?? "204800", 10);
const maxScriptSourceBytes = Number.parseInt(process.env.MAX_SCRIPT_SOURCE_BYTES ?? "102400", 10);
const maxGuiNodes = Number.parseInt(process.env.MAX_GUI_NODES ?? "300", 10);
const pluginBatchLimit = Number.parseInt(process.env.PLUGIN_BATCH_LIMIT ?? "5", 10);
const bridgeVersion = "0.4.0";
const uiAssetCatalog = Object.freeze([
  { key: "classic_basic_square_studs", name: "Basic Square Studs", image: "rbxassetid://78542938995453", theme: "classic", tileSize: 128, defaultTransparency: 0.2, tintable: true },
  { key: "classic_directional_square_studs", name: "Directional Square Studs", image: "rbxassetid://131129096128477", theme: "classic", tileSize: 128, defaultTransparency: 0.2, tintable: true },
  { key: "fantasy_burgundy_leather", name: "Burgundy Leather", image: "rbxassetid://108302665978363", theme: "fantasy", tileSize: 256, defaultTransparency: 0.12, tintable: false },
  { key: "scifi_navy_hex", name: "Sci-Fi Navy Hex", image: "rbxassetid://92250198163836", theme: "scifi", tileSize: 256, defaultTransparency: 0.12, tintable: false },
  { key: "neutral_charcoal_fabric", name: "Charcoal Fabric", image: "rbxassetid://127171928840261", theme: "neutral", tileSize: 256, defaultTransparency: 0.18, tintable: true },
  { key: "fantasy_ivory_gold", name: "Ivory Gold Fantasy", image: "rbxassetid://102797233721198", theme: "fantasy", tileSize: 256, defaultTransparency: 0.08, tintable: false },
  { key: "nature_honey_wood", name: "Honey Wood Nature", image: "rbxassetid://85134607830755", theme: "nature", tileSize: 256, defaultTransparency: 0.1, tintable: false },
  { key: "magic_purple_crystal", name: "Purple Crystal Magic", image: "rbxassetid://93676710714639", theme: "magic", tileSize: 256, defaultTransparency: 0.1, tintable: false }
]);
const uiIconSheets = Object.freeze([
  {
    category: "core",
    image: "rbxassetid://96020281784810",
    keys: ["store", "inventory", "pets", "egg", "trade", "settings", "daily-gift", "trophy", "quests", "teleport", "rebirth", "index", "codes", "boosts", "achievements", "friends", "home", "close", "play", "lock", "unlock", "coin", "gem", "star", "heart", "shield", "sword", "potion", "chest", "crown", "rocket", "magnet", "luck", "timer", "sound", "music"]
  },
  {
    category: "commerce",
    image: "rbxassetid://113147965704973",
    keys: ["shopping-cart", "shopping-basket", "storefront", "price-tag", "cash-register", "wallet", "currency-token", "coin-stack", "gem-pile", "money-bag", "credit-card", "receipt", "sale-badge", "limited-time", "vip-pass", "premium", "gift", "coupon", "product-box", "product-crate", "mystery-box", "lucky-block", "safe", "piggy-bank", "upgrade", "level-up", "multiplier", "discount", "refresh-shop", "restock", "potion-bundle", "egg-bundle", "pet-food", "key-bundle", "boost-bottle", "checkout"]
  },
  {
    category: "gameplay-social",
    image: "rbxassetid://111978857368362",
    keys: ["pet-face", "add-pet", "pet-fusion", "pet-collar", "pet-hatch", "pet-index", "combat", "helmet", "target", "damage", "training", "boss", "run", "jump", "speed", "teleport-world", "world", "compass", "multiplayer", "add-friend", "handshake", "chat", "party", "guild", "mail", "notification", "announcement", "leaderboard", "profile", "report", "farm", "pickaxe", "fishing", "cooking", "crafting", "resources"]
  },
  {
    category: "controls-events",
    image: "rbxassetid://81992493620296",
    keys: ["menu", "more", "back", "forward", "up", "down", "confirm", "cancel", "plus", "minus", "edit", "delete", "visible", "hidden", "camera", "screenshot", "fullscreen", "resize", "volume", "mute", "music-control", "vibration", "keyboard", "controller", "info", "warning", "error", "help", "loading", "cloud-sync", "calendar", "confetti", "fireworks", "snowflake", "hot-streak", "rainbow-luck"]
  }
]);
const uiIconCatalog = Object.freeze(uiIconSheets.flatMap((sheet) =>
  sheet.keys.map((key, index) => ({
    key,
    category: sheet.category,
    image: sheet.image,
    rectOffset: [(index % 6) * 170, Math.floor(index / 6) * 170],
    rectSize: [170, 170]
  }))
));

if (!apiKey || apiKey.length < 16) {
  console.error("BRIDGE_API_KEY must be set to a random value of at least 16 characters.");
  process.exit(1);
}

const allowedActions = new Set([
  "get_tree",
  "search_instances",
  "get_properties",
  "get_selection",
  "search_code",
  "get_output_logs",
  "create_instance",
  "duplicate_instance",
  "move_instance",
  "rename_instance",
  "batch_create",
  "set_properties",
  "set_attributes",
  "set_script_source",
  "patch_script",
  "create_gui",
  "create_weld",
  "create_constraint",
  "set_selection",
  "set_model_pivot",
  "set_tags",
  "execute_plan",
  "terrain_fill_block",
  "terrain_fill_ball",
  "terrain_clear_region",
  "set_studio_camera",
  "delete_instance"
]);

const actionAliases = new Map([
  ["inspect_workspace", "get_tree"],
  ["inspect_tree", "get_tree"],
  ["list_tree", "get_tree"],
  ["list_instances", "get_tree"],
  ["inspect_selection", "get_selection"],
  ["read_properties", "get_properties"],
  ["inspect_properties", "get_properties"],
  ["read_output_logs", "get_output_logs"]
]);

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    "cache-control": "no-store",
    "x-content-type-options": "nosniff"
  });
  res.end(payload);
}

function html(res, title, body) {
  const payload = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${title}</title><style>body{max-width:760px;margin:48px auto;padding:0 20px;font:16px/1.6 system-ui;color:#202124}h1,h2{line-height:1.25}a{color:#0969da}</style><main>${body}</main></html>`;
  res.writeHead(200, {
    "content-type": "text/html; charset=utf-8",
    "content-length": Buffer.byteLength(payload),
    "cache-control": "public, max-age=3600",
    "x-content-type-options": "nosniff"
  });
  res.end(payload);
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxRequestBytes) {
      const error = new Error(`Request body exceeds ${maxRequestBytes} bytes.`);
      error.status = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function constantTimeEqual(left, right) {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map(
      (key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

function countGuiNodes(node) {
  if (!node || typeof node !== "object") return 0;
  return 1 + (Array.isArray(node.children)
    ? node.children.reduce((total, child) => total + countGuiNodes(child), 0)
    : 0);
}

function validateCommandSize(action, args) {
  if (
    (action === "set_script_source" || action === "patch_script")
    && Buffer.byteLength(String(args.source ?? args.replace ?? ""), "utf8") > maxScriptSourceBytes
  ) {
    return `Script content exceeds ${maxScriptSourceBytes} bytes.`;
  }
  if (action === "create_gui" && countGuiNodes(args.tree) > maxGuiNodes) {
    return `GUI tree exceeds ${maxGuiNodes} nodes.`;
  }
  return null;
}

function isActionAuthorized(req) {
  const authorization = req.headers.authorization ?? "";
  const bearer = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  const pluginKey = req.headers["x-bridge-key"] ?? "";
  return constantTimeEqual(String(bearer || pluginKey), apiKey);
}

function deviceCredentials(req) {
  return {
    id: String(req.headers["x-device-id"] ?? ""),
    token: String(req.headers["x-device-token"] ?? "")
  };
}

async function isPluginAuthorized(req, expectedDeviceId) {
  const credentials = deviceCredentials(req);
  const device = await getDevice(credentials.id);
  if (device && (!expectedDeviceId || credentials.id === expectedDeviceId)) {
    return constantTimeEqual(credentials.token, device.token);
  }
  return isActionAuthorized(req) && (!expectedDeviceId || expectedDeviceId === "legacy");
}

async function createPairing() {
  const characters = [
    "ABCDEFGHJKLMNPQRSTUVWXYZ"[randomInt(24)],
    "abcdefghijkmnopqrstuvwxyz"[randomInt(25)],
    "23456789"[randomInt(8)],
    "-_!"[randomInt(3)]
  ];
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789-_!";
  while (characters.length < 12) {
    characters.push(alphabet[randomInt(alphabet.length)]);
  }
  for (let index = characters.length - 1; index > 0; index -= 1) {
    const swapIndex = randomInt(index + 1);
    [characters[index], characters[swapIndex]] = [characters[swapIndex], characters[index]];
  }
  const code = characters.join("");
  const device = {
    id: randomUUID(),
    token: randomBytes(32).toString("base64url"),
    createdAt: new Date().toISOString()
  };
  await saveDevice(device);
  await savePairing(code, {
    deviceId: device.id,
    expiresMs: Date.now() + pairingTtlMs
  }, Math.floor(pairingTtlMs / 1000));
  return { code, device };
}

function cleanupPairings() {
  cleanupMemory(Date.now(), commandTtlMs);
}

function publicCommand(command) {
  return {
    id: command.id,
    deviceId: command.deviceId,
    action: command.action,
    status: command.status,
    createdAt: command.createdAt,
    claimedAt: command.claimedAt ?? null,
    completedAt: command.completedAt ?? null,
    result: command.result ?? null,
    error: command.error ?? null
  };
}

function openApiSchema() {
  return {
    openapi: "3.1.0",
    info: {
      title: "Studio Builder Bridge",
      version: bridgeVersion,
      description: "Queue safe editing commands for a connected game editor plugin."
    },
    servers: [{ url: publicBaseUrl }],
    paths: {
      "/v1/ui-assets": {
        get: {
          operationId: "listRobloxUiAssets",
          summary: "List shared Roblox UI textures",
          description: "Returns moderated image asset IDs and recommended tiling settings for advanced GUI creation. Use these exact image values with create_gui style.texture.",
          responses: {
            "200": {
              description: "Shared UI texture catalog",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    additionalProperties: false,
                    required: ["version", "assets"],
                    properties: {
                      version: { type: "string" },
                      assets: {
                        type: "array",
                        items: {
                          type: "object",
                          required: ["key", "name", "image", "theme", "tileSize", "defaultTransparency", "tintable"],
                          additionalProperties: false,
                          properties: {
                            key: { type: "string" },
                            name: { type: "string" },
                            image: { type: "string" },
                            theme: { type: "string" },
                            tileSize: { type: "integer" },
                            defaultTransparency: { type: "number" },
                            tintable: { type: "boolean" }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "/v1/ui-icons": {
        get: {
          operationId: "listRobloxUiIcons",
          summary: "List shared Roblox simulator UI icons",
          description: "Returns original shared icon atlas IDs and exact ImageRectOffset/ImageRectSize values. Use them on ImageLabel or ImageButton instances.",
          responses: {
            "200": {
              description: "Shared UI icon catalog",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    additionalProperties: false,
                    required: ["version", "icons"],
                    properties: {
                      version: { type: "string" },
                      icons: {
                        type: "array",
                        items: {
                          type: "object",
                          additionalProperties: false,
                          required: ["key", "category", "image", "rectOffset", "rectSize"],
                          properties: {
                            key: { type: "string" },
                            category: { type: "string" },
                            image: { type: "string" },
                            rectOffset: { type: "array", minItems: 2, maxItems: 2, items: { type: "integer" } },
                            rectSize: { type: "array", minItems: 2, maxItems: 2, items: { type: "integer" } }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "/v1/pairings/resolve": {
        post: {
          operationId: "pairRobloxStudio",
          summary: "Resolve a 12-character Studio pairing code",
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  additionalProperties: false,
                  required: ["pairingCode"],
                  properties: {
                    pairingCode: {
                      type: "string",
                      minLength: 12,
                      maxLength: 12,
                      pattern: "^[A-Za-z0-9_!\\-]{12}$",
                      description: "Case-sensitive 12-character pairing code shown in the plugin."
                    }
                  }
                }
              }
            }
          },
          responses: {
            "200": {
              description: "Paired Studio device",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    additionalProperties: false,
                    required: ["paired", "deviceId"],
                    properties: {
                      paired: {
                        type: "boolean",
                        description: "True only when the pairing code was accepted."
                      },
                      deviceId: {
                        type: "string",
                        minLength: 1,
                        description: "Required Studio device ID. Reuse this exact value in every sendRobloxStudioCommand call in this conversation."
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "/v1/commands": {
        post: {
          operationId: "sendRobloxStudioCommand",
          summary: "Send an editing or inspection command to the game editor",
          description: "Inspect hierarchy, selection, properties, code, and Output logs; create and edit instances or direct GUI trees; patch scripts; transform models; manage tags; create welds and constraints. The user approves mutations in Studio. After sending, poll with getRobloxStudioCommandStatus.",
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  additionalProperties: false,
                  required: ["deviceId", "action", "args"],
                  properties: {
                    deviceId: {
                      type: "string",
                      description: "Studio device ID returned by pairRobloxStudio."
                    },
                    action: {
                      type: "string",
                      enum: [...allowedActions]
                    },
                    args: {
                      type: "object",
                      description: "Arguments for the selected action. create_gui tree nodes may include style.cornerRadius; style.corners {topLeft, topRight, bottomRight, bottomLeft}; style.shadow {enabled, color, transparency, offsetX, offsetY, spread, image}; style.texture {image, color, transparency, tileSize, tileWidth, tileHeight}; and style.gradient {rotation, offset, colors, transparency}.",
                      additionalProperties: true,
                      properties: {
                        path: {
                          type: "string",
                          description: "Target instance path, for example Workspace/MyPart or StarterGui/MainGui."
                        },
                        rootPath: {
                          type: "string",
                          description: "Root path for search operations."
                        },
                        parentPath: {
                          type: "string",
                          description: "Parent path for a new or moved instance."
                        },
                        newParentPath: { type: "string" },
                        className: { type: "string" },
                        name: { type: "string" },
                        newName: { type: "string" },
                        maxDepth: { type: "integer", minimum: 0, maximum: 6 },
                        maxResults: { type: "integer", minimum: 1, maximum: 200 },
                        query: { type: "string" },
                        contains: { type: "string" },
                        caseSensitive: { type: "boolean" },
                        limit: { type: "integer", minimum: 1, maximum: 300 },
                        properties: {
                          type: "object",
                          additionalProperties: true
                        },
                        attributes: {
                          type: "object",
                          additionalProperties: true
                        },
                        source: { type: "string" },
                        find: { type: "string" },
                        replace: { type: "string" },
                        replaceAll: { type: "boolean" },
                        items: {
                          type: "array",
                          maxItems: 100,
                          items: { type: "object", additionalProperties: true }
                        },
                        tree: {
                          type: "object",
                          description: "Nested direct GUI tree with className, name, properties, and children.",
                          additionalProperties: true
                        },
                        paths: {
                          type: "array",
                          items: { type: "string" },
                          maxItems: 100
                        },
                        part0Path: { type: "string" },
                        part1Path: { type: "string" },
                        attachment0Path: { type: "string" },
                        attachment1Path: { type: "string" },
                        cframe: {
                          type: "array",
                          items: { type: "number" },
                          minItems: 3,
                          maxItems: 12
                        },
                        focus: {
                          type: "array",
                          items: { type: "number" },
                          minItems: 3,
                          maxItems: 3
                        },
                        size: {
                          type: "array",
                          items: { type: "number" },
                          minItems: 3,
                          maxItems: 3
                        },
                        position: {
                          type: "array",
                          items: { type: "number" },
                          minItems: 3,
                          maxItems: 3
                        },
                        scale: { type: "number" },
                        radius: { type: "number" },
                        material: { type: "string" },
                        add: {
                          type: "array",
                          items: { type: "string" }
                        },
                        remove: {
                          type: "array",
                          items: { type: "string" }
                        },
                        operations: {
                          type: "array",
                          maxItems: 50,
                          items: {
                            type: "object",
                            required: ["action", "args"],
                            properties: {
                              action: { type: "string" },
                              args: { type: "object", additionalProperties: true }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          },
          responses: {
            "202": {
              description: "Command queued",
              content: {
                "application/json": {
                  schema: { $ref: "#/components/schemas/CommandStatus" }
                }
              }
            },
            "429": {
              description: "Per-device command limit reached"
            }
          },
          security: [{ bearerAuth: [] }]
        }
      },
      "/v1/commands/{commandId}": {
        get: {
          operationId: "getRobloxStudioCommandStatus",
          summary: "Check the status and result of a game editor command",
          parameters: [{
            name: "commandId",
            in: "path",
            required: true,
            schema: { type: "string" }
          }],
          responses: {
            "200": {
              description: "Current command state",
              content: {
                "application/json": {
                  schema: { $ref: "#/components/schemas/CommandStatus" }
                }
              }
            }
          },
          security: [{ bearerAuth: [] }]
        }
      }
    },
    components: {
      securitySchemes: {
        bearerAuth: {
          type: "http",
          scheme: "bearer"
        }
      },
      schemas: {
        CommandStatus: {
          type: "object",
          properties: {
            id: { type: "string" },
            action: { type: "string" },
            status: { type: "string", enum: ["queued", "claimed", "completed", "failed"] },
            createdAt: { type: "string" },
            claimedAt: { type: ["string", "null"] },
            completedAt: { type: ["string", "null"] },
            result: {},
            error: { type: ["string", "null"] }
          }
        }
      }
    }
  };
}

function cleanupExpired() {
  cleanupMemory(Date.now(), commandTtlMs);
}

export default async function handler(req, res) {
  try {
    const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);

    if (req.method === "GET" && url.pathname === "/health") {
      return json(res, 200, { ok: true, storage: usesRedis ? "redis" : "memory", ...memoryStats() });
    }

    if (req.method === "GET" && url.pathname === "/privacy") {
      return html(res, "Studio Builder Bridge Privacy Policy", `
        <h1>Studio Builder Bridge Privacy Policy</h1><p>Last updated: July 25, 2026</p>
        <h2>Data processed</h2><p>The service processes a random Studio device identifier and token, temporary 12-character pairing codes, command arguments, timestamps, results, errors, and basic operational logs. It never requires a Roblox password.</p>
        <h2>Purpose and retention</h2><p>Data is used only to route commands to the paired game editor installation, return results, prevent unauthorized access, and diagnose failures. Pairing codes and commands expire automatically. A small recent success/failure history is retained for up to seven days.</p>
        <h2>Sharing and control</h2><p>Data is not sold. Vercel and Upstash may process data solely to operate the service. Users can revoke access with Reset Device, by clearing the plugin pairing, or by uninstalling the plugin. Every Studio mutation requires approval.</p>
        <h2>Contact</h2><p>Support and privacy requests: <a href="https://github.com/ahnminjae08043-glitch/roblox-studio-gpt-bridge/issues">GitHub Issues</a>.</p>`);
    }

    if (req.method === "GET" && url.pathname === "/terms") {
      return html(res, "Studio Builder Bridge Terms", `
        <h1>Studio Builder Bridge Terms</h1><p>This is a development tool. Users must review commands, keep backups, follow applicable platform policies, and test generated changes before publishing. Every mutation requires approval in Studio, and additional requests may wait in the device-specific queue. The hosted service uses fair-use command, daily, queue, and payload limits. A Creator Store purchase is a one-time plugin purchase and does not create a recurring Bridge subscription. The service is provided without a guarantee that generated code is correct or suitable for production.</p>`);
    }

    if (req.method === "GET" && url.pathname === "/openapi.json") {
      return json(res, 200, openApiSchema());
    }

    if (req.method === "GET" && url.pathname === "/v1/ui-assets") {
      return json(res, 200, { version: bridgeVersion, assets: uiAssetCatalog });
    }

    if (req.method === "GET" && url.pathname === "/v1/ui-icons") {
      return json(res, 200, { version: bridgeVersion, icons: uiIconCatalog });
    }

    if (req.method === "POST" && url.pathname === "/v1/plugin/pairings") {
      cleanupPairings();
      const { code, device } = await createPairing();
      return json(res, 201, {
        pairingCode: code,
        expiresInSeconds: Math.floor(pairingTtlMs / 1000),
        deviceId: device.id,
        deviceToken: device.token
      });
    }

    if (req.method === "POST" && url.pathname === "/v1/pairings/resolve") {
      if (!isActionAuthorized(req)) return json(res, 401, { error: "Unauthorized" });
      cleanupPairings();
      const body = await readJson(req);
      const code = String(body.pairingCode ?? "").trim();
      const pairing = await takePairing(code);
      if (!pairing) return json(res, 404, { error: "Pairing code is invalid or expired." });
      return json(res, 200, {
        paired: true,
        deviceId: pairing.deviceId
      });
    }

    const pluginRoute = url.pathname.startsWith("/v1/plugin/");
    if (!pluginRoute && !isActionAuthorized(req)) {
      return json(res, 401, { error: "Unauthorized" });
    }

    if (req.method === "POST" && url.pathname === "/v1/commands") {
      const body = await readJson(req);
      const payload = body.command ?? body.input ?? body;
      const action = actionAliases.get(payload.action) ?? payload.action;
      const deviceId = String(payload.deviceId ?? "legacy").trim();
      if (deviceId !== "legacy" && !(await getDevice(deviceId))) {
        return json(res, 404, {
          error: "Unknown deviceId. Pair this Studio installation again.",
          errorCode: "STALE_DEVICE_ID",
          reconnectRequired: true
        });
      }
      let args = payload.args ?? {};
      if (typeof args === "string") {
        try {
          args = args.trim() === "" ? {} : JSON.parse(args);
        } catch {
          return json(res, 400, { error: "args must be a JSON object, not an invalid JSON string." });
        }
      }
      if (!allowedActions.has(action) || !args || typeof args !== "object" || Array.isArray(args)) {
        return json(res, 400, { error: "Invalid action or args." });
      }
      const sizeError = validateCommandSize(action, args);
      if (sizeError) return json(res, 413, { error: sizeError });

      const globalRateLimit = await consumeRateLimit(
        "commands:global",
        globalCommandLimit,
        globalCommandWindowSeconds
      );
      if (!globalRateLimit.allowed) {
        return json(res, 503, {
          error: "The Bridge is temporarily busy. Try again shortly.",
          retryAfterSeconds: globalRateLimit.retryAfterSeconds
        });
      }

      const shortRateLimit = await consumeRateLimit(
        `commands:${deviceId}`,
        deviceCommandLimit,
        deviceCommandWindowSeconds
      );
      if (!shortRateLimit.allowed) {
        return json(res, 429, {
          error: `Command limit reached. Try again in ${shortRateLimit.retryAfterSeconds} seconds.`,
          limit: deviceCommandLimit,
          windowSeconds: deviceCommandWindowSeconds,
          retryAfterSeconds: shortRateLimit.retryAfterSeconds
        });
      }
      const dailyRateLimit = await consumeRateLimit(
        `commands-daily:${deviceId}`,
        dailyCommandLimit,
        86400
      );
      if (!dailyRateLimit.allowed) {
        return json(res, 429, {
          error: `Daily command limit of ${dailyCommandLimit} reached.`,
          limit: dailyCommandLimit,
          windowSeconds: 86400,
          retryAfterSeconds: dailyRateLimit.retryAfterSeconds
        });
      }

      const queueCount = await countQueuedCommands(deviceId);
      if (queueCount >= maxDeviceQueue) {
        return json(res, 429, {
          error: `Device queue is full. Approve or reject pending commands first.`,
          queueCount,
          maxQueue: maxDeviceQueue
        });
      }
      const command = {
        id: randomUUID(),
        action,
        args,
        deviceId,
        status: "queued",
        createdAt: new Date().toISOString(),
        createdMs: Date.now()
      };
      if (deviceId !== "legacy") {
        const dedupeKey = createHash("sha256")
          .update(`${deviceId}:${action}:${stableStringify(args)}`)
          .digest("hex");
        const reservedCommandId = await reserveDedupe(
          dedupeKey,
          command.id,
          Math.floor(commandTtlMs / 1000)
        );
        if (reservedCommandId !== command.id) {
          const existing = await getCommand(reservedCommandId);
          if (existing) return json(res, 200, { ...publicCommand(existing), duplicate: true });
        }
      }
      await saveCommand(command, Math.floor(commandTtlMs / 1000));
      return json(res, 202, publicCommand(command));
    }

    const statusMatch = url.pathname.match(/^\/v1\/commands\/([0-9a-f-]+)$/i);
    if (req.method === "GET" && statusMatch) {
      const command = await getCommand(statusMatch[1]);
      return command ? json(res, 200, publicCommand(command)) : json(res, 404, { error: "Command not found." });
    }

    if (req.method === "GET" && url.pathname === "/v1/plugin/commands/next") {
      const credentials = deviceCredentials(req);
      const deviceId = credentials.id || "legacy";
      if (!(await isPluginAuthorized(req, deviceId))) return json(res, 401, { error: "Unauthorized" });
      cleanupExpired();
      const requestedLimit = Math.max(
        1,
        Math.min(pluginBatchLimit, Number.parseInt(url.searchParams.get("limit") ?? "1", 10) || 1)
      );
      const commands = await claimCommands(
        deviceId,
        requestedLimit,
        Math.floor(commandTtlMs / 1000)
      );
      const queueCount = await countQueuedCommands(deviceId);
      const shortUsage = await getRateLimitStatus(`commands:${deviceId}`, deviceCommandLimit);
      const dailyUsage = await getRateLimitStatus(`commands-daily:${deviceId}`, dailyCommandLimit);
      return json(res, 200, {
        version: bridgeVersion,
        queueCount,
        usage: {
          shortRemaining: shortUsage.remaining,
          dailyRemaining: dailyUsage.remaining
        },
        command: commands[0] ? {
          id: commands[0].id,
          action: commands[0].action,
          args: commands[0].args
        } : null,
        commands: commands.map((command) => ({
          id: command.id,
          action: command.action,
          args: command.args
        }))
      });
    }

    if (req.method === "POST" && url.pathname === "/v1/plugin/commands/reject-all") {
      const credentials = deviceCredentials(req);
      if (!(await isPluginAuthorized(req, credentials.id))) {
        return json(res, 401, { error: "Unauthorized" });
      }
      const rejected = await rejectQueuedCommands(
        credentials.id,
        Math.floor(commandTtlMs / 1000),
        "Rejected by the user in Roblox Studio."
      );
      return json(res, 200, { rejected });
    }

    if (req.method === "GET" && url.pathname === "/v1/plugin/status") {
      const credentials = deviceCredentials(req);
      if (!(await isPluginAuthorized(req, credentials.id))) {
        return json(res, 401, { error: "Unauthorized" });
      }
      const shortUsage = await getRateLimitStatus(`commands:${credentials.id}`, deviceCommandLimit);
      const dailyUsage = await getRateLimitStatus(
        `commands-daily:${credentials.id}`,
        dailyCommandLimit
      );
      return json(res, 200, {
        version: bridgeVersion,
        queueCount: await countQueuedCommands(credentials.id),
        usage: {
          shortRemaining: shortUsage.remaining,
          dailyRemaining: dailyUsage.remaining
        },
        history: await getHistory(credentials.id, 5)
      });
    }

    if (req.method === "DELETE" && url.pathname === "/v1/plugin/device") {
      const credentials = deviceCredentials(req);
      if (!(await isPluginAuthorized(req, credentials.id))) {
        return json(res, 401, { error: "Unauthorized" });
      }
      await rejectQueuedCommands(
        credentials.id,
        Math.floor(commandTtlMs / 1000),
        "Device connection was reset."
      );
      await deleteDevice(credentials.id);
      return json(res, 200, { revoked: true });
    }

    const resultMatch = url.pathname.match(/^\/v1\/plugin\/commands\/([0-9a-f-]+)\/result$/i);
    if (req.method === "POST" && resultMatch) {
      const command = await getCommand(resultMatch[1]);
      if (!command) return json(res, 404, { error: "Command not found." });
      if (!(await isPluginAuthorized(req, command.deviceId))) {
        return json(res, 401, { error: "Unauthorized" });
      }
      const body = await readJson(req);
      command.status = body.ok ? "completed" : "failed";
      command.result = body.ok ? (body.result ?? {}) : null;
      command.error = body.ok ? null : String(body.error ?? "Unknown plugin error");
      command.completedAt = new Date().toISOString();
      await saveCommand(command, Math.floor(commandTtlMs / 1000));
      await recordHistory(command.deviceId, {
        id: command.id,
        action: command.action,
        ok: body.ok === true,
        completedAt: command.completedAt,
        error: body.ok ? null : String(body.error ?? "Unknown error").slice(0, 300)
      });
      return json(res, 200, publicCommand(command));
    }

    return json(res, 404, { error: "Not found" });
  } catch (error) {
    const status = Number(error.status) || (error instanceof SyntaxError ? 400 : 500);
    return json(res, status, { error: error.message });
  }
}

if (!process.env.VERCEL) {
  const server = http.createServer(handler);
  server.listen(port, "127.0.0.1", () => {
    console.log(`Roblox GPT Bridge listening on http://127.0.0.1:${port}`);
    console.log(`OpenAPI schema: http://127.0.0.1:${port}/openapi.json`);
  });
}
