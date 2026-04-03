<!--
SYNC IMPACT REPORT
==================
Version change:        [template/unversioned] → 1.0.0
Version bump type:     MINOR (initial constitution — all principles newly defined)

Principles added:
  • I. Code Quality
  • II. Testing Standards (NON-NEGOTIABLE)
  • III. User Experience Consistency
  • IV. Performance Requirements

Sections added:
  • Core Principles (4 principles)
  • Quality Gates
  • Development Workflow
  • Governance

Sections removed:      N/A (template placeholders replaced)

Template alignment:
  ✅ .specify/templates/plan-template.md
     — Constitution Check section uses dynamic gate resolution; gates now map to the
       4 principles defined here. No structural change required.
  ✅ .specify/templates/spec-template.md
     — Success Criteria and Functional Requirements sections align with Performance
       Requirements and UX Consistency principles. No structural change required.
  ✅ .specify/templates/tasks-template.md
     — Test-first task phases (T010-T011 pattern) align with Testing Standards
       principle. No structural change required.
  ✅ .github/agents/speckit.constitution.agent.md
     — No CLAUDE-specific references found; guidance is agent-agnostic.

Deferred TODOs:        None — all placeholders resolved.
-->

# Moodle Demo Site Constitution

## Core Principles

### I. Code Quality

All code submitted to this project MUST meet the following standards:

- Code MUST be readable and self-documenting; complex logic MUST include inline
  comments explaining intent, not mechanism.
- Functions and methods MUST follow the single-responsibility principle; any unit
  exceeding ~40 lines warrants justification in the PR.
- Dead code, commented-out blocks, and unused imports MUST NOT be merged.
- Linting and static analysis MUST pass with zero errors before any PR is merged.
- Dependencies MUST be pinned to explicit versions; floating ranges are prohibited
  in production manifests.

**Rationale**: Consistent code quality reduces review overhead, lowers defect rates,
and ensures the codebase remains maintainable as the team grows.

### II. Testing Standards (NON-NEGOTIABLE)

- Tests MUST be written before implementation (TDD); the Red-Green-Refactor cycle
  is strictly enforced on all new features.
- Unit test coverage MUST be ≥ 80% on all new modules; coverage regressions block
  merging.
- Integration tests MUST cover every user-facing flow defined in spec.md user
  stories before the story is considered complete.
- End-to-end (E2E) tests MUST cover P1 user stories; P2 and below SHOULD have E2E
  coverage where feasible.
- Tests MUST be deterministic and isolated — no shared global state, no reliance
  on test execution order, no external network calls without mocking.
- Flaky tests MUST be fixed or quarantined within one sprint of being identified.

**Rationale**: Testing discipline is the primary defence against regressions in a
Moodle environment where course data integrity and learner progress are critical.

### III. User Experience Consistency

- All UI components MUST conform to the established design system (tokens,
  typography scale, spacing grid); one-off styles are prohibited without design
  review.
- Interactive elements MUST meet WCAG 2.1 AA accessibility standards; this includes
  keyboard navigation, ARIA labelling, and a minimum contrast ratio of 4.5:1.
- Error messages MUST be human-readable, actionable, and consistent in tone and
  format across the entire application.
- Navigation patterns and interaction flows MUST remain consistent across feature
  areas; divergent patterns require explicit design approval.
- Every user-facing string MUST be sourced from the localisation layer; hard-coded
  display text is prohibited.

**Rationale**: Learners and educators rely on predictable, accessible interfaces.
Inconsistent UX increases cognitive load and reduces completion rates.

### IV. Performance Requirements

- Page load time (Time to Interactive) MUST be ≤ 3 seconds on a 4G connection for
  all P1 user flows under normal load.
- API endpoints MUST respond within 500 ms at p95 under the defined target load.
- Database queries introduced by a feature MUST be reviewed for index usage;
  queries performing full table scans on tables with > 10 k rows are prohibited
  without explicit justification.
- Front-end bundles MUST not increase the total page weight by more than 50 kB
  (gzipped) per feature without a performance budget review.
- Performance benchmarks MUST be recorded in the plan.md of each feature so
  regressions are detectable across releases.

**Rationale**: Moodle platforms are often accessed on low-bandwidth connections and
shared devices. Performance is a feature, not an afterthought.

## Quality Gates

All features MUST pass the following gates before being considered shippable:

- **Gate 1 — Static Analysis**: Linter and type-checker report zero errors.
- **Gate 2 — Test Suite**: All tests pass; coverage thresholds met (≥ 80% on new
  modules); no newly introduced flaky tests.
- **Gate 3 — Accessibility Audit**: Automated a11y scan (e.g., axe-core) reports
  zero critical or serious violations on changed pages.
- **Gate 4 — Performance Budget**: Lighthouse or equivalent score does not regress
  below the recorded baseline for P1 flows.
- **Gate 5 — UX Review**: Any changed UI components reviewed against the design
  system; deviations documented and approved.

A feature that fails any gate MUST NOT be merged to the main branch.

## Development Workflow

- Branches MUST be named using sequential numbering per project convention
  (e.g., `001-feature-name`).
- Every PR MUST reference its corresponding spec.md and include a self-review
  checklist confirming compliance with each Core Principle.
- PRs MUST have at least one peer review approval before merging.
- All CI checks (lint, tests, accessibility scan) MUST be green before a reviewer
  is requested.
- Breaking changes to shared APIs or data schemas MUST be accompanied by a
  migration plan documented in the feature's plan.md.
- Hotfixes bypass the standard spec workflow but MUST still pass all Quality Gates.

## Governance

This constitution supersedes all ad-hoc team conventions. Where a situational
decision conflicts with a principle, the principle takes precedence unless a formal
amendment is ratified.

**Amendment procedure**:
1. Propose the change in a dedicated PR against `.specify/memory/constitution.md`.
2. Summarise the rationale, the version bump type, and the list of dependent
   artifacts that require updating.
3. Obtain approval from at least two project maintainers.
4. Update the version line, `LAST_AMENDED_DATE`, and the Sync Impact Report comment
   before merging.

**Versioning policy** (semantic):
- MAJOR — Principle removed or its non-negotiable rules fundamentally redefined.
- MINOR — New principle added or a section materially expanded.
- PATCH — Wording clarification, typo fix, non-semantic refinement.

**Compliance review**: Each sprint retrospective SHOULD include a brief check that
recent work has adhered to all four principles. Persistent violations MUST trigger
a constitution amendment or a corrective action plan.

**Version**: 1.0.0 | **Ratified**: 2026-04-03 | **Last Amended**: 2026-04-03
