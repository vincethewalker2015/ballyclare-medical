# P3 closure and Phase 6 readiness review

Date: 2026-11-02
Branch: `security-andauthorization-audit`

## P3.1.6 — Medical Group Architecture: closed for agreed foundation scope

Delivered:
- Medical group ownership boundary with practice-specific operational records.
- Same-group staff practice switching and role-aware local membership selection.
- Selected-practice patient, booking, appointment, diary and availability safeguards.
- Clinician-only appointment and availability restrictions.
- Encounter and clinical-note practice-ownership model validation.
- Staff User Manual instructions for multi-practice working.

Verification: user reported the full RSpec suite passing after the final role-boundary regression specs, and manually confirmed that the User Manual renders correctly.

Deferred, not counted as delivered: a single cross-practice patient-search/booking experience and staff-facing clinical consultation/note workflows. The latter are planned in Phase 6. Existing practice switching does not imply global patient search or clinical-record access.

## Remaining Phase 5 P3 — Approved documents and communications

The roadmap calls for access to explicitly approved patient documents, appropriately scoped messages, and verification of production email delivery before relying on notifications.

Initial route-level assessment (`config/routes.rb`):
- No patient-portal document listing/download or secure-message routes are currently declared.
- No staff document approval/release or secure-message routes are currently declared.
- Authentication, invitation and confirmation emails are separate from a delivered patient communications workflow.

**Status: not verified complete.** Route absence alone is not proof that there are no supporting models or mailers. Before implementation, agree the minimum patient document types, staff approval/release rules, whether in-app secure messaging is in Phase 5 scope, and notification requirements.

Suggested minimum acceptance:
1. Patient sees only documents explicitly released to their verified, approved practice-specific patient account; never drafts or other patients' records.
2. Staff can release/revoke documents only within authorised practice and role boundaries; every release and access-sensitive change is auditable.
3. Communications, if included in scope, are recipient- and practice-scoped with explicit permission rules, delivery failure handling and no clinical details in email subject lines.
4. Verify actual production email configuration/delivery; passing mailer specs is not sufficient.
5. Request and system tests cover unauthorised access, revoked account links, sibling practices, unrelated groups, and file/download privacy.

## Phase 5 acceptance gate before Phase 6

The roadmap explicitly requires final Phase 5 security, accessibility, cross-practice isolation, permission and operational checks and sign-off. A passing RSpec suite is necessary but not a substitute for manual browser, email delivery and operational verification.

## Phase 6 preparation

Phase 6 is **Appointment Lifecycle and Clinical Workflow**. Start only after the Phase 5 gate. Its planned clinician consultation workspace includes authorised appointment access, encounter start, draft notes, signing, amendments with preserved history, appointment completion, and comprehensive role/audit safeguards.

Do not expand P3.1.6 with Phase 6 consultation UI work.
