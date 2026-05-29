import { createServer } from "node:http";
import { attachPlantVisionRelay } from "./relay.js";

const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "0.0.0.0";

const httpServer = createServer();
attachPlantVisionRelay(httpServer, {
  corsOrigin: process.env.CORS_ORIGIN || "*"
});

httpServer.listen(port, host, () => {
  console.log(`PlantVision Socket.IO relay listening on ${host}:${port}`);
});
