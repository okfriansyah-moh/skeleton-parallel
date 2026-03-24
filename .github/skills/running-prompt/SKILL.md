---
name: running-prompt
description: "This skill defines a structured workflow for executing tasks, including planning, implementation, security review, verification, and issue remediation. It ensures that all tasks are completed securely, verified, and approved before final confirmation. Optimized for Principal Engineer execution standards."
---

## Trigger

Use this skill when:

- You have a clear task that requires implementation, security review, and verification.
- You need to ensure a structured workflow with explicit user approval before completion.
- You want to maintain high standards of security, reliability, and performance in your implementations.
- You want to optimize for deterministic and production-grade outputs while allowing controlled exploration during planning.
- You want to ensure that all critical decisions are clarified with the user before implementation.
- You want to ensure that all issues are remediated before confirming completion.
- running-prompt is designed to guide you through a comprehensive task execution process, ensuring that all aspects of the implementation are thoroughly planned, securely implemented, and rigorously verified before final approval and completion confirmation.

---

# Task Execution Workflow

Follow the steps below to handle the tasks effectively.

---

# 0. Principal Engineer Temperature Configuration

Set temperature dynamically based on task type, optimized for deterministic and production-grade execution.

## Temperature Profile

| Task Category                      | Temperature | Rationale                                       |
| ---------------------------------- | ----------- | ----------------------------------------------- |
| Implementation / Execution         | **0.15**    | Deterministic, precise, production-safe output  |
| Research / Planning / Architecture | **0.45**    | Controlled exploration with trade-off reasoning |
| Security Review / Audit            | **0.2**     | Deterministic threat modeling                   |
| Verification / Analysis            | **0.2**     | Accurate validation without creative deviation  |
| Remediation / Fixing               | **0.15**    | Precise issue resolution                        |

---

## Temperature Rules

- Never exceed **0.5** for production work.
- Use **≤ 0.2** for:
  - Security-sensitive systems
  - Financial systems
  - Authentication / authorization
  - Data pipelines

- Lower temperature = higher determinism and auditability.

---

# 1. Planning via Subagent

Use the **subagent** to thoroughly plan the tasks.

Return the implementation plan complete with:

- Technical details
- Architecture decisions
- Confirmed critical approaches
- Identified risks
- Mitigation strategies
- Performance considerations
- Security implications

---

## Mandatory Clarification

The planning subagent **must use the askQuestion tool** to clarify uncertainties and confirm important technical approaches with the user.

This includes anything affecting:

- Functional behavior
- Resiliency
- Security
- Robustness
- Performance
- Reliability
- Cost efficiency
- Scalability

No assumptions are allowed on critical decisions.

---

# 2. Immediate Implementation

Immediately perform the implementation according to the approved plan on the **main agent**, without ending the session.

Follow:

- `AGENTS.md` standards
- Security best practices
- Reliability engineering principles
- Performance optimization guidelines

Implementation must strictly align with approved planning outputs.

---

# 3. Parallel Post-Implementation Review

After implementation, run **two subagents in parallel**:

---

## 3a. Security Review Mode

Perform a comprehensive security assessment.

### Report must include:

- Security issues identified
- Estimated CVSS score
- Risk severity classification
- Exploit scenarios
- Attack vectors
- Compliance gaps
- Recommended remediations

### Coverage Areas

- Input validation
- Injection risks
- AuthN / AuthZ
- Secrets handling
- Data exposure
- Dependency vulnerabilities
- Configuration risks

---

## 3b. Verification Mode

Perform technical verification including:

- Build validation
- Static code analysis
- Automated tests
- Linting
- Type checking
- Coverage validation

### Report must include:

- Build failures
- Test failures
- Code quality issues
- Type violations
- Coverage gaps

---

# 4. Issue Remediation Loop

If any issues are found:

1. Fix all issues immediately
2. Re-implement corrections
3. Re-run Step 3 (parallel reviews)

Repeat until:

- No security findings remain
- No verification issues remain

Zero-issue state is mandatory.

---

# 5. Pre-Completion Approval Gate

Before generating the final summary or completion confirmation:

You **must use the askQuestion tool** to obtain explicit user approval.

---

## Approval Request Must Include

- Implementation summary
- Key technical decisions
- Security review status
- Verification status
- Risks (if any)
- Trade-offs made

⚠️ Final summary is **forbidden** before approval is granted.

---

# 6. Completion Confirmation

Once approval is received and no issues remain, confirm that the implementation is:

- Complete
- Secure
- Verified
- To-do list checked

And has passed:

- Security review
- Verification checks
- Quality gates
- Make sure todo list is fully checked off
- Make sure all issues are remediated
- Make sure codebase error-free and production-ready
- Do not make duplicate files with suffix 2, example : readme 2.md, implementation_roadmap 2.md, etc. If you need to update the content, update the original file instead of creating a new one.
- Do not make duplicate folders with suffix 2, example : docs 2/, etc. If you need to add new content, add it to the original folder instead of creating a new one.

Then, provide the final confirmation of task completion.
