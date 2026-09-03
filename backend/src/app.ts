import cors from "cors";
import express from "express";
import { errorMiddleware } from "./middleware/error.middleware";
import { routes } from "./routes";

export const app = express();

app.use(cors());
app.use(express.json());

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "coordit-backend" });
});

app.use(routes);
app.use(errorMiddleware);
