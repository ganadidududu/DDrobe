import { executeProfileStylingOperatorConnectionProbe } from "./profile-styling-schema-reconciliation.operator-connection-probe";

void executeProfileStylingOperatorConnectionProbe(process.env).then((exitCode) => {
  process.exitCode = exitCode;
});
