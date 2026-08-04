import cors from "cors";
import express from "express";
import { errorMiddleware } from "./middleware/error.middleware";
import { routes } from "./routes";
import { env } from "./config/env";

export const app = express();

app.use(
  cors({
    origin: (origin, callback) => {
      if (origin === undefined || env.corsOrigins.includes(origin)) {
        callback(null, true);
        return;
      }

      callback(null, false);
    }
  })
);
app.use(express.json());

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "coordit-backend" });
});

app.use(routes);
app.use(errorMiddleware);
