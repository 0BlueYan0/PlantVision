import assert from "node:assert/strict";
import { createServer } from "node:http";
import { after, before, test } from "node:test";
import { io as connectClient } from "socket.io-client";
import { attachPlantVisionRelay } from "../src/relay.js";

let httpServer;
let relay;
let relayURL;

before(async () => {
  httpServer = createServer();
  relay = attachPlantVisionRelay(httpServer);
  await new Promise((resolve) => httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = httpServer.address();
  relayURL = `http://127.0.0.1:${port}`;
});

after(async () => {
  relay.close();
  await new Promise((resolve) => httpServer.close(resolve));
});

test("relays Mac frame JSON to Vision client in the same pairing room", async () => {
  const mac = connectClient(relayURL, { transports: ["websocket"] });
  const vision = connectClient(relayURL, { transports: ["websocket"] });

  try {
    await Promise.all([waitForConnect(mac), waitForConnect(vision)]);

    mac.emit("join", { role: "mac", code: "482913" });
    vision.emit("join", { role: "vision", code: "482913" });

    await Promise.all([
      waitForEvent(mac, "joined"),
      waitForEvent(vision, "joined")
    ]);

    const receivedPromise = waitForEvent(vision, "plantVisionRelay");
    mac.emit("frameResult", {
      type: "frameCaptured",
      message: "成功抽幀",
      frameWidth: 2560,
      frameHeight: 1664
    });

    const received = await receivedPromise;
    assert.equal(received.code, "482913");
    assert.equal(received.data.message, "成功抽幀");
    assert.equal(received.data.type, "frameCaptured");
  } finally {
    mac.disconnect();
    vision.disconnect();
  }
});

test("relays the optional witherRatio / witherLevel fields through to Vision", async () => {
  const mac = connectClient(relayURL, { transports: ["websocket"] });
  const vision = connectClient(relayURL, { transports: ["websocket"] });

  try {
    await Promise.all([waitForConnect(mac), waitForConnect(vision)]);

    mac.emit("join", { role: "mac", code: "482913" });
    vision.emit("join", { role: "vision", code: "482913" });
    await Promise.all([
      waitForEvent(mac, "joined"),
      waitForEvent(vision, "joined")
    ]);

    const receivedPromise = waitForEvent(vision, "plantVisionRelay");
    mac.emit("frameResult", {
      type: "frameCaptured",
      message: "成功抽幀",
      plantID: "lantana-camara",
      confidence: 0.8,
      witherRatio: 0.42,
      witherLevel: 2
    });

    const received = await receivedPromise;
    // relay 整包轉發，枯萎欄位應原封不動傳到 vision
    assert.equal(received.data.witherRatio, 0.42);
    assert.equal(received.data.witherLevel, 2);
  } finally {
    mac.disconnect();
    vision.disconnect();
  }
});

test("relays the optional yellowRatio / yellowLevel / witherTrend fields through to Vision", async () => {
  const mac = connectClient(relayURL, { transports: ["websocket"] });
  const vision = connectClient(relayURL, { transports: ["websocket"] });

  try {
    await Promise.all([waitForConnect(mac), waitForConnect(vision)]);

    mac.emit("join", { role: "mac", code: "482913" });
    vision.emit("join", { role: "vision", code: "482913" });
    await Promise.all([
      waitForEvent(mac, "joined"),
      waitForEvent(vision, "joined")
    ]);

    const receivedPromise = waitForEvent(vision, "plantVisionRelay");
    mac.emit("frameResult", {
      type: "frameCaptured",
      message: "成功抽幀",
      plantID: "lantana-camara",
      confidence: 0.8,
      witherRatio: 0.42,
      witherLevel: 2,
      yellowRatio: 0.5,
      yellowLevel: 2,
      witherTrend: "worsening"
    });

    const received = await receivedPromise;
    // relay 整包轉發，黃化與趨勢欄位應原封不動傳到 vision
    assert.equal(received.data.yellowRatio, 0.5);
    assert.equal(received.data.yellowLevel, 2);
    assert.equal(received.data.witherTrend, "worsening");
  } finally {
    mac.disconnect();
    vision.disconnect();
  }
});

test("does not relay Mac frame JSON to a different pairing room", async () => {
  const mac = connectClient(relayURL, { transports: ["websocket"] });
  const vision = connectClient(relayURL, { transports: ["websocket"] });

  try {
    await Promise.all([waitForConnect(mac), waitForConnect(vision)]);

    mac.emit("join", { role: "mac", code: "111111" });
    vision.emit("join", { role: "vision", code: "222222" });
    await Promise.all([
      waitForEvent(mac, "joined"),
      waitForEvent(vision, "joined")
    ]);

    let received = false;
    vision.on("plantVisionRelay", () => {
      received = true;
    });
    mac.emit("frameResult", { message: "成功抽幀" });
    await new Promise((resolve) => setTimeout(resolve, 100));

    assert.equal(received, false);
  } finally {
    mac.disconnect();
    vision.disconnect();
  }
});

function waitForConnect(socket) {
  return new Promise((resolve, reject) => {
    socket.once("connect", resolve);
    socket.once("connect_error", reject);
  });
}

function waitForEvent(socket, event) {
  return new Promise((resolve) => {
    socket.once(event, resolve);
  });
}
