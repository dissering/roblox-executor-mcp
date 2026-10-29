import { z } from "zod";

export const threadContextSchema = z
  .number()
  .describe(
    "Requested thread identity (default: 8). If the executor cannot change identity, execution keeps its current permissions."
  )
  .optional()
  .default(8);

export const maxOutputCharsSchema = z
  .number()
  .describe(
    "Maximum characters to return to the model (default: 6000, max: 32000). Raise only when a single result genuinely needs more; large outputs degrade model performance."
  )
  .optional()
  .default(6000);
