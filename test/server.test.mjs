import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";

const port = 18787;
const key = "test-key-that-is-long-enough";
let child;

test.before(async () => {
  child = spawn(process.execPath, ["server.mjs"], {
    cwd: new URL("..", import.meta.url),
    env: { ...process.env, PORT: String(port), BRIDGE_API_KEY: key },
    stdio: "ignore"
  });
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/health`);
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("Test server did not start.");
});

test.after(() => {
  child?.kill();
});

test("rejects missing authentication", async () => {
  const response = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ action: "get_tree", args: {} })
  });
  assert.equal(response.status, 401);
});

test("rejects an action outside the allowlist", async () => {
  const response = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ action: "run_arbitrary_lua", args: {} })
  });
  assert.equal(response.status, 400);
});

test("accepts omitted, stringified, wrapped, and aliased inspection args", async () => {
  const cases = [
    { action: "get_tree" },
    { action: "get_tree", args: "{\"path\":\"Workspace\"}" },
    { command: { action: "inspect_workspace", args: { path: "Workspace" } } }
  ];

  for (const body of cases) {
    const response = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${key}`,
        "content-type": "application/json"
      },
      body: JSON.stringify(body)
    });
    assert.equal(response.status, 202);
    const command = await response.json();
    assert.equal(command.action, "get_tree");

    const claimResponse = await fetch(`http://127.0.0.1:${port}/v1/plugin/commands/next`, {
      headers: { "x-bridge-key": key }
    });
    const claimed = await claimResponse.json();
    assert.equal(claimed.command.id, command.id);

    await fetch(`http://127.0.0.1:${port}/v1/plugin/commands/${command.id}/result`, {
      method: "POST",
      headers: {
        "x-bridge-key": key,
        "content-type": "application/json"
      },
      body: JSON.stringify({ ok: true, result: {} })
    });
  }
});

test("advertises the expanded action set", async () => {
  const response = await fetch(`http://127.0.0.1:${port}/openapi.json`);
  const schema = await response.json();
  const actions = schema.paths["/v1/commands"].post.requestBody.content["application/json"].schema.properties.action.enum;
  const argumentSchema = schema.paths["/v1/commands"].post.requestBody.content["application/json"].schema.properties.args;
  assert.ok(actions.includes("create_gui"));
  assert.ok(actions.includes("batch_create"));
  assert.ok(actions.includes("create_weld"));
  assert.ok(actions.includes("search_instances"));
  assert.ok(actions.includes("patch_script"));
  assert.ok(actions.includes("get_output_logs"));
  assert.ok(actions.includes("set_model_pivot"));
  assert.ok(actions.includes("create_constraint"));
  assert.ok(actions.includes("execute_plan"));
  assert.ok(actions.includes("terrain_fill_block"));
  assert.ok(actions.includes("set_studio_camera"));
  assert.equal(argumentSchema.properties.path.type, "string");
  assert.equal(argumentSchema.properties.parentPath.type, "string");
  assert.equal(argumentSchema.properties.tree.type, "object");
  assert.equal(argumentSchema.properties.operations.type, "array");

  const pluginSource = await readFile(new URL("../plugin/RobloxGPTBridge.server.lua", import.meta.url), "utf8");
  assert.doesNotMatch(pluginSource, /AlwaysAllow|alwaysAllow/);
  assert.match(pluginSource, /or awaitApproval\(command\)/);
  assert.match(pluginSource, /urlBox\.TextEditable = false/);
  const handlers = new Set([...pluginSource.matchAll(/function handlers\.([a-z_]+)/g)].map((match) => match[1]));
  assert.deepEqual(actions.filter((action) => !handlers.has(action)), []);
});

test("queues, claims, and completes a command", async () => {
  const createResponse = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ action: "get_tree", args: { path: "Workspace" } })
  });
  assert.equal(createResponse.status, 202);
  const created = await createResponse.json();

  const claimResponse = await fetch(`http://127.0.0.1:${port}/v1/plugin/commands/next`, {
    headers: { "x-bridge-key": key }
  });
  const claimed = await claimResponse.json();
  assert.equal(claimed.command.id, created.id);

  const resultResponse = await fetch(`http://127.0.0.1:${port}/v1/plugin/commands/${created.id}/result`, {
    method: "POST",
    headers: {
      "x-bridge-key": key,
      "content-type": "application/json"
    },
    body: JSON.stringify({ ok: true, result: { name: "Workspace" } })
  });
  assert.equal(resultResponse.status, 200);

  const statusResponse = await fetch(`http://127.0.0.1:${port}/v1/commands/${created.id}`, {
    headers: { authorization: `Bearer ${key}` }
  });
  const status = await statusResponse.json();
  assert.equal(status.status, "completed");
  assert.deepEqual(status.result, { name: "Workspace" });
});

test("pairs a Studio device and isolates its command queue", async () => {
  const pairingResponse = await fetch(`http://127.0.0.1:${port}/v1/plugin/pairings`, {
    method: "POST"
  });
  assert.equal(pairingResponse.status, 201);
  const pairing = await pairingResponse.json();
  assert.match(pairing.pairingCode, /^[A-Za-z0-9_!-]{12}$/);
  assert.match(pairing.pairingCode, /[A-Z]/);
  assert.match(pairing.pairingCode, /[a-z]/);
  assert.match(pairing.pairingCode, /[0-9]/);
  assert.match(pairing.pairingCode, /[-_!]/);

  const resolveResponse = await fetch(`http://127.0.0.1:${port}/v1/pairings/resolve`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ pairingCode: pairing.pairingCode })
  });
  assert.equal(resolveResponse.status, 200);
  assert.equal((await resolveResponse.json()).deviceId, pairing.deviceId);

  const createResponse = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      deviceId: pairing.deviceId,
      action: "get_tree",
      args: { path: "Workspace" }
    })
  });
  assert.equal(createResponse.status, 202);
  const command = await createResponse.json();

  const legacyClaim = await fetch(`http://127.0.0.1:${port}/v1/plugin/commands/next`, {
    headers: { "x-bridge-key": key }
  });
  assert.equal((await legacyClaim.json()).command, null);

  const deviceHeaders = {
    "x-device-id": pairing.deviceId,
    "x-device-token": pairing.deviceToken
  };
  const deviceClaim = await fetch(`http://127.0.0.1:${port}/v1/plugin/commands/next`, {
    headers: deviceHeaders
  });
  assert.equal((await deviceClaim.json()).command.id, command.id);

  const wrongResult = await fetch(
    `http://127.0.0.1:${port}/v1/plugin/commands/${command.id}/result`,
    {
      method: "POST",
      headers: {
        ...deviceHeaders,
        "x-device-token": "wrong-token",
        "content-type": "application/json"
      },
      body: JSON.stringify({ ok: true, result: {} })
    }
  );
  assert.equal(wrongResult.status, 401);
});
