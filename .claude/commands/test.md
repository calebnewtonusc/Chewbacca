---
description: Write comprehensive tests: Vitest unit tests + Playwright E2E sketch for a component or function
allowed-tools: Bash(npm:*), Bash(npx:*), Bash(grep:*), Read, Write, Glob
argument-hint: "<file path or component/function name>"
---

# Test

Write comprehensive tests for `$ARGUMENTS`.

## Step 1: Understand what to test

Read the target file. Extract:

- What is the **primary behavior**? (what does the happy path do)
- What are the **edge cases**? (empty, null, max length, invalid input)
- What **side effects** exist? (DB writes, API calls, state changes)
- What **error cases** should be handled?

## Step 2: Check test infrastructure

```bash
# Check what test runner is configured
cat package.json | grep -A 5 '"scripts"' | grep test
cat vitest.config.ts 2>/dev/null || cat vitest.config.js 2>/dev/null || echo "No vitest config found"
```

If Vitest isn't configured:

```bash
npm install -D vitest @testing-library/react @testing-library/user-event @testing-library/jest-dom jsdom
```

Add to `package.json`:

```json
{
  "scripts": {
    "test": "vitest",
    "test:run": "vitest run",
    "test:ui": "vitest --ui"
  }
}
```

## Step 3: Write unit tests

Create `{filename}.test.ts` or `{filename}.test.tsx` adjacent to the source file.

### For a pure function

```typescript
import { describe, it, expect } from "vitest";
import { functionName } from "./{filename}";

describe("functionName", () => {
  // Happy path
  it("returns correct result for valid input", () => {
    expect(functionName("valid input")).toBe("expected output");
  });

  // Edge cases
  it("handles empty string", () => {
    expect(functionName("")).toBe("");
  });

  it("handles null gracefully", () => {
    expect(() => functionName(null as any)).not.toThrow();
  });

  // Error cases
  it("throws on invalid input type", () => {
    expect(() => functionName(123 as any)).toThrow("Expected string");
  });
});
```

### For an async function

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

describe("asyncFunction", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns data on success", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: true,
      json: async () => ({ id: "1", name: "Test" }),
    } as Response);

    const result = await asyncFunction("1");
    expect(result).toEqual({ id: "1", name: "Test" });
  });

  it("throws on network error", async () => {
    vi.spyOn(global, "fetch").mockRejectedValueOnce(new Error("Network error"));
    await expect(asyncFunction("1")).rejects.toThrow("Network error");
  });

  it("handles non-ok response", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: false,
      status: 404,
    } as Response);
    await expect(asyncFunction("1")).rejects.toThrow();
  });
});
```

### For a React component

```typescript
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ComponentName } from "./{filename}";

describe("ComponentName", () => {
  const defaultProps = {
    // minimum required props
  };

  it("renders without crashing", () => {
    render(<ComponentName {...defaultProps} />);
    expect(screen.getByRole("main")).toBeInTheDocument();
  });

  it("shows loading state", () => {
    render(<ComponentName {...defaultProps} isLoading={true} />);
    expect(screen.getByRole("status")).toBeInTheDocument(); // skeleton
  });

  it("shows error state", () => {
    render(<ComponentName {...defaultProps} error="Something went wrong" />);
    expect(screen.getByText(/something went wrong/i)).toBeInTheDocument();
  });

  it("shows empty state when no data", () => {
    render(<ComponentName {...defaultProps} data={[]} />);
    expect(screen.getByText(/no .* found/i)).toBeInTheDocument();
  });

  it("renders items when data is present", () => {
    const mockData = [{ id: "1", name: "Item 1" }];
    render(<ComponentName {...defaultProps} data={mockData} />);
    expect(screen.getByText("Item 1")).toBeInTheDocument();
  });

  it("calls onAction when button is clicked", async () => {
    const onAction = vi.fn();
    render(<ComponentName {...defaultProps} onAction={onAction} />);
    await userEvent.click(screen.getByRole("button", { name: /action/i }));
    expect(onAction).toHaveBeenCalledOnce();
  });
});
```

### For an API route (Next.js)

```typescript
import { describe, it, expect, vi } from "vitest";
import { GET, POST } from "./{route}";

describe("GET /api/resource", () => {
  it("returns 401 when not authenticated", async () => {
    vi.mock("@/lib/supabase", () => ({
      createServerClient: () => ({
        auth: { getUser: async () => ({ data: { user: null } }) },
      }),
    }));

    const req = new Request("http://localhost/api/resource");
    const res = await GET(req as any);
    expect(res.status).toBe(401);
  });

  it("returns data when authenticated", async () => {
    // mock auth + DB
    const res = await GET(req as any);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toHaveProperty("data");
  });
});
```

## Step 4: E2E test sketch (Playwright)

If Playwright is installed, create `{feature}.spec.ts` in `tests/e2e/`:

```typescript
import { test, expect } from "@playwright/test";

test.describe("{Feature}", () => {
  test("happy path, user can {main action}", async ({ page }) => {
    await page.goto("/");

    // Step 1: Navigate to feature
    await page.getByRole("link", { name: /feature/i }).click();

    // Step 2: Interact
    await page.getByRole("button", { name: /start/i }).click();
    await page.getByLabel(/name/i).fill("Test Name");
    await page.getByRole("button", { name: /submit/i }).click();

    // Step 3: Assert success
    await expect(page.getByText(/success/i)).toBeVisible();
  });

  test("shows error on invalid input", async ({ page }) => {
    await page.goto("/feature");
    await page.getByRole("button", { name: /submit/i }).click();
    await expect(page.getByRole("alert")).toBeVisible();
  });
});
```

## Step 5: Run the tests

```bash
npm run test:run 2>&1 | tail -30
```

All tests must pass. If any fail, fix the source code (not the test) unless the test itself is wrong.

## Coverage rule

After writing tests, ensure these are covered:

- [ ] Happy path passes
- [ ] Loading state renders correctly
- [ ] Error state renders correctly
- [ ] Empty state renders correctly
- [ ] All user interactions (clicks, input) call the right handlers
- [ ] Network errors don't crash the component
- [ ] TypeScript compiles with zero errors in test file
