import http from "node:http";
import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import {
  claimCommand,
  cleanupMemory,
  getCommand,
  getDevice,
  memoryStats,
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
    if (size > 256 * 1024) {
      throw new Error("Request body is too large.");
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
  const code = String(Math.floor(100000 + Math.random() * 900000));
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
      title: "Roblox Studio Bridge",
      version: "0.1.0",
      description: "Queue safe editing commands for a connected Roblox Studio plugin."
    },
    servers: [{ url: publicBaseUrl }],
    paths: {
      "/v1/pairings/resolve": {
        post: {
          operationId: "pairRobloxStudio",
          summary: "Resolve a six-digit Studio pairing code",
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
                      pattern: "^[0-9]{6}$"
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
                    properties: { deviceId: { type: "string" } }
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
          summary: "Send an editing or inspection command to Roblox Studio",
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
                      description: "Arguments for the selected action.",
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
            }
          },
          security: [{ bearerAuth: [] }]
        }
      },
      "/v1/commands/{commandId}": {
        get: {
          operationId: "getRobloxStudioCommandStatus",
          summary: "Check the status and result of a Roblox Studio command",
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
      return html(res, "Roblox Studio Bridge Privacy Policy", `
        <h1>Roblox Studio Bridge Privacy Policy</h1><p>Last updated: July 25, 2026</p>
        <h2>Data processed</h2><p>The service processes a random Studio device identifier and token, temporary six-digit pairing codes, command arguments, timestamps, results, errors, and basic operational logs. It never requires a Roblox password.</p>
        <h2>Purpose and retention</h2><p>Data is used only to route commands to the paired Roblox Studio installation, return results, prevent unauthorized access, and diagnose failures. Pairing codes and commands expire automatically. Operational logs are retained only as needed for security and reliability.</p>
        <h2>Sharing and control</h2><p>Data is not sold. Vercel and Upstash may process data solely to operate the service. Users can revoke access by clearing the plugin pairing or uninstalling the plugin. Studio mutations require approval unless Always Allow is enabled.</p>
        <h2>Contact</h2><p>Support and privacy requests: <a href="https://github.com/ahnminjae08043-glitch/roblox-studio-gpt-bridge/issues">GitHub Issues</a>.</p>`);
    }

    if (req.method === "GET" && url.pathname === "/terms") {
      return html(res, "Roblox Studio Bridge Terms", `
        <h1>Roblox Studio Bridge Terms</h1><p>This is a development tool. Users must review commands, keep backups, follow Roblox and OpenAI policies, and test generated changes before publishing. Always Allow may automatically execute destructive edits and should be enabled only for a trusted GPT and Bridge server. The service is provided without a guarantee that generated code is correct or suitable for production.</p>`);
    }

    if (req.method === "GET" && url.pathname === "/openapi.json") {
      return json(res, 200, openApiSchema());
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
      const code = String(body.pairingCode ?? "").replace(/\D/g, "");
      const pairing = await takePairing(code);
      if (!pairing) return json(res, 404, { error: "Pairing code is invalid or expired." });
      return json(res, 200, { deviceId: pairing.deviceId });
    }

    const pluginRoute = url.pathname.startsWith("/v1/plugin/");
    if (!pluginRoute && !isActionAuthorized(req)) {
      return json(res, 401, { error: "Unauthorized" });
    }

    if (req.method === "POST" && url.pathname === "/v1/commands") {
      const body = await readJson(req);
      const payload = body.command ?? body.input ?? body;
      const action = actionAliases.get(payload.action) ?? payload.action;
      const deviceId = String(payload.deviceId ?? "legacy");
      if (deviceId !== "legacy" && !(await getDevice(deviceId))) {
        return json(res, 404, { error: "Unknown deviceId. Pair this Studio installation first." });
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
      const command = {
        id: randomUUID(),
        action,
        args,
        deviceId,
        status: "queued",
        createdAt: new Date().toISOString(),
        createdMs: Date.now()
      };
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
      const command = await claimCommand(deviceId, Math.floor(commandTtlMs / 1000));
      if (!command) return json(res, 200, { command: null });
      if (command.status === "queued") {
        command.status = "claimed";
        command.claimedAt = new Date().toISOString();
        await saveCommand(command, Math.floor(commandTtlMs / 1000));
      }
      return json(res, 200, {
        command: {
          id: command.id,
          action: command.action,
          args: command.args
        }
      });
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
      return json(res, 200, publicCommand(command));
    }

    return json(res, 404, { error: "Not found" });
  } catch (error) {
    const status = error instanceof SyntaxError ? 400 : 500;
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
