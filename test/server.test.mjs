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
    env: {
      ...process.env,
      PORT: String(port),
      BRIDGE_API_KEY: key,
      DEVICE_COMMAND_LIMIT: "10",
      DEVICE_COMMAND_WINDOW_SECONDS: "600"
    },
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
    assert.ok([200, 202].includes(response.status));
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
  assert.match(argumentSchema.description, /style\.corners \{topLeft, topRight, bottomRight, bottomLeft\}/);
  assert.equal(argumentSchema.properties.path.type, "string");
  assert.equal(argumentSchema.properties.parentPath.type, "string");
  assert.equal(argumentSchema.properties.tree.type, "object");
  assert.equal(argumentSchema.properties.operations.type, "array");

  const pluginSource = await readFile(new URL("../plugin/RobloxGPTBridge.server.lua", import.meta.url), "utf8");
  assert.doesNotMatch(pluginSource, /AlwaysAllow|alwaysAllow/);
  assert.match(pluginSource, /or awaitApproval\(command\)/);
  assert.match(pluginSource, /urlBox\.TextEditable = false/);
  assert.match(pluginSource, /INACTIVE_POLL_SECONDS = 20\.0/);
  assert.match(pluginSource, /Reject All Queued Commands/);
  assert.match(pluginSource, /\/v1\/plugin\/commands\/next\?limit=5/);
  assert.match(pluginSource, /Offline - retrying in %ds/);
  assert.match(pluginSource, /local corners = style\.corners/);
  assert.match(pluginSource, /__GPTShadow/);
  assert.match(pluginSource, /style\.cornerRadius/);
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
  const resolvedPairing = await resolveResponse.json();
  assert.equal(resolvedPairing.paired, true);
  assert.equal(resolvedPairing.deviceId, pairing.deviceId);

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
  const duplicateResponse = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
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
  assert.equal(duplicateResponse.status, 200);
  const duplicate = await duplicateResponse.json();
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.id, command.id);

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

test("claims commands in batches and rejects the remaining queue", async () => {
  const pairingResponse = await fetch(`http://127.0.0.1:${port}/v1/plugin/pairings`, {
    method: "POST"
  });
  const pairing = await pairingResponse.json();
  await fetch(`http://127.0.0.1:${port}/v1/pairings/resolve`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ pairingCode: pairing.pairingCode })
  });

  for (let index = 0; index < 3; index += 1) {
    const response = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${key}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        deviceId: pairing.deviceId,
        action: "get_tree",
        args: { path: `Workspace/Batch${index}` }
      })
    });
    assert.equal(response.status, 202);
  }

  const deviceHeaders = {
    "x-device-id": pairing.deviceId,
    "x-device-token": pairing.deviceToken
  };
  const batchResponse = await fetch(
    `http://127.0.0.1:${port}/v1/plugin/commands/next?limit=2`,
    { headers: deviceHeaders }
  );
  const batch = await batchResponse.json();
  assert.equal(batch.commands.length, 2);
  assert.equal(batch.queueCount, 1);

  const rejectResponse = await fetch(
    `http://127.0.0.1:${port}/v1/plugin/commands/reject-all`,
    {
      method: "POST",
      headers: {
        ...deviceHeaders,
        "content-type": "application/json"
      },
      body: "{}"
    }
  );
  assert.equal(rejectResponse.status, 200);
  assert.equal((await rejectResponse.json()).rejected, 1);
});

test("limits command creation per paired device", async () => {
  const pairingResponse = await fetch(`http://127.0.0.1:${port}/v1/plugin/pairings`, {
    method: "POST"
  });
  const pairing = await pairingResponse.json();
  const resolveResponse = await fetch(`http://127.0.0.1:${port}/v1/pairings/resolve`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ pairingCode: pairing.pairingCode })
  });
  assert.equal(resolveResponse.status, 200);

  for (let index = 0; index < 10; index += 1) {
    const response = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${key}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        deviceId: pairing.deviceId,
        action: "get_tree",
        args: { path: `Workspace/Test${index}` }
      })
    });
    assert.equal(response.status, 202);
  }

  const limitedResponse = await fetch(`http://127.0.0.1:${port}/v1/commands`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      deviceId: pairing.deviceId,
      action: "get_tree",
      args: { path: "Workspace/OverLimit" }
    })
  });
  assert.equal(limitedResponse.status, 429);
  const limited = await limitedResponse.json();
  assert.equal(limited.limit, 10);
  assert.ok(limited.retryAfterSeconds > 0);
});
