Policy
 Jira project management, Tested are one of required state in the definition of done — a feature isn't "done" without tested
 CI enforces a minimum coverage or mutation-testing threshold and fails the build below it
 Code review checklist explicitly flags untestable patterns (hidden state, hard-coded dependencies, etc.)
 CICD AI code review pre-screen check list : see below CICD AI check list 
 Whoever writes the feature writes its tests — no throw-it-over-the-wall to a separate QA team
 Estimates and sprint planning include test-writing time, so it isn't cut under deadline pressure
 Flaky tests are treated as bugs and fixed or quarantined, not ignored
 Document Magic number reasoning and historical changes.
 Simulation enviroment are created along with development.
 
Design
 Dependencies (network, filesystem, clock, database, randomness) are injected, not reached for directly
 Business logic is separated from side effects — pure functions in, I/O pushed to the edges
 Units (functions/classes) are small and single-responsibility, limiting the states to cover
 Code depends on interfaces/abstractions, not concrete implementations, so test doubles can substitute
 No hidden global/static mutable state that lets tests bleed into each other or depend on order
 Time, randomness, and environment are abstracted behind seams (e.g., a clock interface) instead of called directly
 

Implementation
 Tests are written alongside or before the code (TesDrivenDevelopment or close to it), not bolted on after
 Functions are deterministic — same input always produces same output, no reliance on ambient state
 Dependency injection is used consistently across the codebase, not just where convenient
 Logging/instrumentation is structured so tests can assert on behavior, not scrape text output
 Logging functional debug logging need able to enable/disable real time.
 Test data is built via factories/builders rather than copy-pasted fixtures, so it doesn't rot
 Each test is independent and can run in isolation or in any order


CICD AI check list
	Boundary & input validation

	Off-by-one and boundary values (min, max, zero, empty string/array, single-element collection)
	Null/undefined/None handling before dereference or method call
	Type coercion, integer overflow/underflow, floating-point precision loss
	Unicode/encoding edge cases and locale-dependent formatting (dates, decimals, sorting)
	unit conformaty (Exsample Fahrenheit and Celsius class/type that can't be implicitly mixed) 

	Error handling & resilience

	Swallowed exceptions (empty catch blocks, catching too broad a type)
	Missing or incorrect error propagation across function/service boundaries
	Timeout handling for external calls (network, DB, disk)
	Retry logic correctness — is the retried operation actually idempotent?
	Resource cleanup on failure paths (unclosed files, sockets, connections, unreleased locks)
	Graceful degradation vs. hard crash on partial failure

	Concurrency & process handling

	Race conditions on shared mutable state
	Deadlock/livelock risk from lock ordering
	Atomicity of multi-step operations (partial writes, non-atomic read-modify-write)
	Cancellation and graceful shutdown (does a task actually stop when told to?)
	Resource exhaustion from unbounded queues, threads, or recursion

	State & control flow

	Invalid state transitions in state machines
	Idempotency of operations that might be called twice (e.g., webhook handlers, retried API calls)
	Correct handling of empty/no-op cases (empty input list, zero matching records)

	Security-adjacent checks

	Injection vectors (SQL, command, path traversal) in newly added input handling
	Hard-coded secrets or credentials introduced in the diff
	Missing authorization/authentication checks on new endpoints
	Sensitive data logged in plaintext

	Test quality itself

	New code paths introduced without corresponding test coverage
	Tests that assert too little (no real assertion, or only "doesn't throw")
	Over-mocked tests that no longer exercise real logic
	Flaky-test patterns: sleep-based waits, test-order dependency, shared fixture state
	Coverage regression relative to the base branch

	Compatibility & contracts

	Breaking changes to public API signatures or return types
	Backward compatibility of serialized data formats (schema changes)
	Config/environment variable validation (missing defaults, required-but-unset values)
