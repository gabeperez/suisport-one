import Fastify from "fastify";
import { authRoutes } from "./routes/auth.js";
import { workoutRoutes } from "./routes/workouts.js";
import { healthRoutes } from "./routes/health.js";
import { config } from "./config.js";

async function main() {
  const app = Fastify({ logger: true });

  app.register(authRoutes, { prefix: "/auth" });
  app.register(workoutRoutes, { prefix: "/workouts" });
  app.register(healthRoutes, { prefix: "/health" });

  await app.listen({ port: config.port, host: "0.0.0.0" });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
