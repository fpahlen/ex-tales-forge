---
name: pragmatic-broken-windows
description: Detect and immediately fix or flag broken windows including bad designs poor code wrong decisions style violations or neglected issues. Activate during code generation review debugging or any time entropy or technical debt appears.
---

# Pragmatic Broken Windows

## Overview

One broken window left unrepaired invites more. Software entropy spreads when small defects are ignored. Pragmatic programmers never live with broken windows.

## Instructions

- Treat every piece of bad design wrong decision poor code or neglected defect as a broken window
- Fix or board up the problem as soon as it is discovered — never leave it for later
- If a proper fix is not possible right now comment it out replace with a clear stub or add an explicit TODO that makes the defect visible
- When generating code refuse to introduce new broken windows even under time pressure
- During review highlight every broken window and insist on action before accepting the change
- Prefer a clean system with fewer features over a feature-rich system that is already decaying
- Remember that neglect accelerates rot faster than almost any other factor

## Key Test

Would you be proud to leave this code as the example for the rest of the team If the answer is no it is a broken window.