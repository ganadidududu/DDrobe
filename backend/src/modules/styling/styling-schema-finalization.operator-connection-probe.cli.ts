import { executeStylingSchemaFinalizationConnectionProbe } from "./styling-schema-finalization.operator-connection-probe";

void executeStylingSchemaFinalizationConnectionProbe(process.env).then((exitCode) => {
  process.exitCode = exitCode;
});
