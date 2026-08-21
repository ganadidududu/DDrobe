import { executeOperatorConnectionProbe } from "./monetization-schema-reconciliation.operator-connection-probe";

void executeOperatorConnectionProbe(process.env).then((exitCode) => {
  process.exitCode = exitCode;
});
