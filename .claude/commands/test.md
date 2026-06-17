Run the DBAOps Pester test suite at Tests\DBAOps.Tests.ps1 using PowerShell.

Execute the tests with: `Invoke-Pester .\Tests\DBAOps.Tests.ps1 -Output Detailed`

Report the results clearly:
- If all tests pass: confirm the count and that the project is clean.
- If any tests fail: list each failing test by name, show the failure message, and explain what it means in plain terms (e.g. a broken :r include path means a Setup script will fail at deploy time). Do not just repeat the raw Pester output — translate it into actionable findings.
