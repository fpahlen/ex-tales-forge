---
name: pragmatic-no-coincidence
description: Reject or question any code that appears to work by coincidence rather than deliberate design. Activate when evaluating generated implementations tests examples or solutions whose success cannot be clearly explained.
---

# Pragmatic No Coincidence

## Overview

Programming by coincidence means relying on code that happens to work without understanding why. This creates fragile systems that break when conditions change. Deliberate programming is required.

## Instructions

- Never accept code simply because it produces the expected result in the current example or test
- Demand a clear explanation of why the solution works under the relevant conditions and boundary cases
- If you cannot articulate the reasoning behind a generated fragment treat it as coincidental and rewrite or reject it
- Prefer explicit contracts assertions and named intermediate results over clever implicit behavior
- When tests pass ask what assumptions they rely on and whether those assumptions are documented and enforced
- Avoid relying on accidental language features environment details or ordering that are not part of the intentional design
- If a change in input data library version or timing would silently break the code it was programmed by coincidence

## Key Test

Can you explain exactly why this works and what would make it stop working If the answer is vague or relies on luck rewrite it.