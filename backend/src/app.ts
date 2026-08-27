import cors from "cors";
import express from "express";
import { env } from "./config/env";
import { errorMiddleware } from "./middleware/error.middleware";
import { privacyPageHtml, supportPageHtml } from "./public-pages";
import { routes } from "./routes";

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

app.get("/support", (_req, res) => {
  res.type("html").send(supportPageHtml);
});

app.get("/privacy", (_req, res) => {
  res.type("html").send(privacyPageHtml);
});

app.use(routes);
app.use(errorMiddleware);
