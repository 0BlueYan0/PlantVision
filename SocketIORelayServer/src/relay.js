import { Server } from "socket.io";

const VALID_ROLES = new Set(["mac", "vision"]);
const MAX_FRAME_RESULT_BYTES = 16 * 1024;

export function attachPlantVisionRelay(httpServer, options = {}) {
  const io = new Server(httpServer, {
    cors: {
      origin: options.corsOrigin ?? "*"
    },
    maxHttpBufferSize: MAX_FRAME_RESULT_BYTES
  });

  io.on("connection", (socket) => {
    socket.data.roomCode = null;
    socket.data.role = null;

    socket.on("join", (payload = {}) => {
      const role = String(payload.role ?? "");
      const code = normalizePairingCode(payload.code);

      if (!VALID_ROLES.has(role) || !code) {
        socket.emit("relayError", {
          type: "invalidJoin",
          message: "join requires role mac/vision and a pairing code"
        });
        return;
      }

      leaveCurrentRoom(socket);

      socket.data.roomCode = code;
      socket.data.role = role;
      socket.join(roomName(code));
      socket.join(roleRoomName(code, role));
      socket.emit("joined", { code, role });
    });

    socket.on("frameResult", (payload = {}) => {
      if (socket.data.role !== "mac" || !socket.data.roomCode) {
        socket.emit("relayError", {
          type: "notJoinedAsMac",
          message: "frameResult is accepted only after joining as mac"
        });
        return;
      }

      const byteLength = Buffer.byteLength(JSON.stringify(payload), "utf8");
      if (byteLength > MAX_FRAME_RESULT_BYTES) {
        socket.emit("relayError", {
          type: "messageTooLarge",
          message: "frameResult exceeds 16 KB"
        });
        return;
      }

      socket.to(roleRoomName(socket.data.roomCode, "vision")).emit("plantVisionRelay", {
        code: socket.data.roomCode,
        data: payload
      });
    });

    socket.on("disconnect", () => {
      leaveCurrentRoom(socket);
    });
  });

  return io;
}

function leaveCurrentRoom(socket) {
  if (!socket.data.roomCode || !socket.data.role) return;

  socket.leave(roomName(socket.data.roomCode));
  socket.leave(roleRoomName(socket.data.roomCode, socket.data.role));
  socket.data.roomCode = null;
  socket.data.role = null;
}

function normalizePairingCode(code) {
  const normalized = String(code ?? "").trim();
  if (!/^[A-Za-z0-9-]{4,32}$/.test(normalized)) return null;
  return normalized;
}

function roomName(code) {
  return `pair:${code}`;
}

function roleRoomName(code, role) {
  return `pair:${code}:${role}`;
}
