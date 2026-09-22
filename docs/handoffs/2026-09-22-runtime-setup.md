# Runtime setup and onboarding changes

Commit `147dd8243bc9d4960bc8f30acbbcbc2936d3945e` contains the shared runtime
and onboarding work described here. Its commit message was accidentally reused
from an older Git editor file after a pre-commit refusal. That message does not
describe this change; this note corrects the record without rewriting history.

The change introduces shared private context and skill discovery, separate
Claude/Codex adapters, platform profiles, reversible setup, blank context
initialization, explicit identity, and clearer onboarding and privacy guidance.
It also fixes formatter runtime selection and hook-health reporting, and includes
the previously staged Swift symbol reporting change in `bin/peel`.

Validation before publication: 51 installer checks and 19 backend checks passed
with a working Node runtime. Generated instructions, checksums, shell syntax and
the added Python modules were checked. The user explicitly authorized publishing
all current repository changes to main and requested that closeout not run.

Native hook trust and actual interception must be verified in the host. Windows
execution was not tested on a Windows machine. Installation alone is not evidence
that every runtime capability is active.
