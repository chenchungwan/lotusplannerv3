# Quality Freeze Checklist

Use this order for the hardening freeze.

1. Logging and security
   - Production verbose logging is off by default.
   - API keys remain in Keychain or user-owned secure storage.
   - No secrets are committed.

2. Concurrency warnings
   - Main-actor UI mutations are explicit.
   - Notification callbacks hop to the main actor before touching view state.
   - Remaining warnings are triaged or ticketed.

3. Task and calendar loading
   - Loading states say which account or data type is loading.
   - Partial failures are visible.
   - Retry is available near the error.
   - Last successful Google fetch is visible in Diagnostics.

4. Navigation and sheets
   - Hamburger menu routes are single-source.
   - Sheets use one presentation path per screen.
   - Dismissal works on iPad and Mac Catalyst.

5. Large-view decomposition
   - Extract focused helpers/components from the largest SwiftUI files.
   - Move data orchestration into view models/services.
   - Keep behavior-preserving splits small enough to review.

6. UX polish
   - Empty states explain what happened and what to do next.
   - Sync and loading indicators do not flicker.
   - Quality/Diagnostics gives support-ready status at a glance.

Release gate:
- `xcodebuild build` succeeds.
- `xcodebuild test` succeeds.
- SwiftLint passes or new violations are explicitly waived.
- Warning count is at or below the current budget.
