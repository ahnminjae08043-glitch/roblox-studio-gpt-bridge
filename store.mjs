const redisUrl = process.env.UPSTASH_REDIS_REST_URL?.replace(/\/+$/, "");
const redisToken = process.env.UPSTASH_REDIS_REST_TOKEN;
export const usesRedis = Boolean(redisUrl && redisToken);

const memoryCommands = new Map();
const memoryDevices = new Map();
const memoryPairings = new Map();

async function redis(...command) {
  const response = await fetch(redisUrl, {
    method: "POST",
    headers: {
      authorization: `Bearer ${redisToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify(command)
  });
  const body = await response.json();
  if (!response.ok || body.error) throw new Error(body.error ?? `Redis HTTP ${response.status}`);
  return body.result;
}

export async function saveCommand(command, ttlSeconds) {
  if (!usesRedis) {
    memoryCommands.set(command.id, command);
    return;
  }
  await redis("SET", `command:${command.id}`, JSON.stringify(command), "EX", ttlSeconds);
  if (command.status === "queued") {
    await redis("RPUSH", `queue:${command.deviceId}`, command.id);
    await redis("EXPIRE", `queue:${command.deviceId}`, ttlSeconds);
  }
}

export async function getCommand(id) {
  if (!usesRedis) return memoryCommands.get(id) ?? null;
  const value = await redis("GET", `command:${id}`);
  return value ? JSON.parse(value) : null;
}

export async function claimCommand(deviceId, ttlSeconds) {
  if (!usesRedis) {
    return [...memoryCommands.values()].find(
      (item) => item.status === "queued" && item.deviceId === deviceId
    ) ?? null;
  }
  while (true) {
    const id = await redis("LPOP", `queue:${deviceId}`);
    if (!id) return null;
    const command = await getCommand(id);
    if (command?.status === "queued") {
      command.status = "claimed";
      command.claimedAt = new Date().toISOString();
      await redis("SET", `command:${id}`, JSON.stringify(command), "EX", ttlSeconds);
      return command;
    }
  }
}

export async function saveDevice(device, ttlSeconds = 15552000) {
  if (!usesRedis) {
    memoryDevices.set(device.id, device);
    return;
  }
  await redis("SET", `device:${device.id}`, JSON.stringify(device), "EX", ttlSeconds);
}

export async function getDevice(id) {
  if (!usesRedis) return memoryDevices.get(id) ?? null;
  const value = await redis("GET", `device:${id}`);
  return value ? JSON.parse(value) : null;
}

export async function savePairing(code, pairing, ttlSeconds) {
  if (!usesRedis) {
    memoryPairings.set(code, pairing);
    return;
  }
  await redis("SET", `pairing:${code}`, JSON.stringify(pairing), "EX", ttlSeconds);
}

export async function takePairing(code) {
  if (!usesRedis) {
    const pairing = memoryPairings.get(code) ?? null;
    memoryPairings.delete(code);
    return pairing;
  }
  const value = await redis("GETDEL", `pairing:${code}`);
  return value ? JSON.parse(value) : null;
}

export function cleanupMemory(now, commandTtlMs) {
  if (usesRedis) return;
  for (const [id, command] of memoryCommands) {
    if (now - command.createdMs > commandTtlMs) memoryCommands.delete(id);
  }
  for (const [code, pairing] of memoryPairings) {
    if (pairing.expiresMs <= now) memoryPairings.delete(code);
  }
}

export function memoryStats() {
  return {
    queued: [...memoryCommands.values()].filter((item) => item.status === "queued").length
  };
}
