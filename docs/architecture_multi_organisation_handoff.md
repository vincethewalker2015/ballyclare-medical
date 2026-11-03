# Multi-organisation architecture handoff

This document describes the Ballyclare Medical implementation on the `architectural-edits` branch and how to reuse its design in a different business domain.

## Domain translation

| Ballyclare Medical | Other platform |
| --- | --- |
| MedicalGroup | Customer group / parent account |
| Practice | Organisation |
| Patient | Client |
| PatientAccount | ClientAccount |
| PatientAccountLink | ClientAccountLink |
| PatientRegistrationRequest | ClientRegistrationRequest |
| StaffMember | OrganisationMembership |
| User | Staff login |
| Clinical records, appointments | Organisation-specific business records |

A **customer group can own multiple organisations**. An organisation belongs to exactly one group. Operational records belong to an organisation, not directly to a login or the parent group.

## Existing relationships reused

- `MedicalGroup has_many :practices` and `Practice belongs_to :medical_group` already implement the parent-child tenancy structure.
- `User has_many :staff_members`; each `StaffMember` belongs to one practice and grants a role there. The same login may have multiple active memberships.
- `Patient belongs_to :practice`; records, appointments, consultations and other operational data remain practice-scoped.
- `PatientAccount` is a separate Devise authentication identity. `PatientAccountLink` is a separately approved link to exactly one practice patient record.
- `PatientRegistrationRequest` records confirmation, verification, approval and completion status, with a separate asynchronous completion job.
- The selected staff practice is stored in the session. The selected practice requires an active membership at that practice; sharing a parent group alone is insufficient.

## Changes in this branch

1. A senior staff administrator can list, create and edit practices within their own medical group through `Staff::PracticesController`. A new practice automatically receives a local senior-administrator membership for its creator. Practice creation, membership and audit are transactional.
2. The staff navigation calls the existing registration-request workflow **Patient accounts**. Internal route and model names remain unchanged to avoid unnecessary migrations.
3. An administrator can invite an existing patient to the portal from the patient's details page.
4. An administrator can also tick **Send a portal invitation** while creating a patient. The existing patient creation action creates the record and, when selected, the account and request in one database transaction. If invitation creation fails, the new patient record is rolled back.
5. Both invitation entry points call `PatientAccounts::CreateInvitation`; neither duplicates the account/request/audit creation logic.
6. A portal invitation creates an unconfirmed `PatientAccount` and an `awaiting_review` `PatientRegistrationRequest`, and initiates Devise email confirmation and password setup. It does **not** create an approved `PatientAccountLink`.
7. Staff can see requests awaiting email confirmation in **Patient accounts**. The existing verify and approve endpoints still require confirmed email and the existing identity checks.

## Lifecycle

```text
Staff selects Organisation
  -> creates Client record (no online account required)
  -> optionally invites Client
       -> ClientAccount (unconfirmed)
       -> ClientRegistrationRequest (awaiting_review)
       -> Client confirms email and chooses password
       -> administrator verifies identity and correct Organisation/Client record
       -> senior administrator approves
       -> completion job creates approved ClientAccountLink
       -> portal may read only approved Organisation/Client data
```

For an existing client, begin at the optional invitation step. Do not duplicate the client record.

## Isolation and authorization invariants

- Always load clients via `current_organisation.clients.find(params[:id])`, not `Client.find(params[:id])`.
- Group ownership does not imply unrestricted cross-organisation data access. Check active local membership, role, and selected organisation on every staff action.
- Validate that selected clients, approvers and verifiers belong to the organisation on the request.
- An email match, confirmed email or staff-issued invitation is never sufficient proof of client identity.
- The approved account link is the portal authorization boundary. The portal must scope every query through the approved link's organisation and client IDs.
- Keep role and staff identities separate from client portal identities. Do not set client passwords on behalf of the client.
- Prevent duplicate client-to-account links with both model validations and unique database indexes.
- Keep approval and revocation auditable. Never log sensitive registration or business data in plaintext.
- Do not assume two organisations in the same group may share client data.

## Implementation pointers

- `app/models/medical_group.rb`, `practice.rb`, `staff_member.rb`, `patient.rb`
- `app/models/patient_account.rb`, `patient_account_link.rb`, `patient_registration_request.rb`
- `app/controllers/staff/practices_controller.rb`
- `app/controllers/staff/patients_controller.rb`
- `app/controllers/staff/patient_portal_invitations_controller.rb`
- `app/services/patient_accounts/create_invitation.rb`
- `app/controllers/staff/patient_account_requests_controller.rb`
- `app/jobs/complete_patient_registration_job.rb`
- `spec/requests/staff/patient_creation_invitations_spec.rb`

## Adaptation checklist

1. Rename the domain concepts, not the security boundaries.
2. Retain separate staff and client authentication models and organisation memberships.
3. Use one shared invitation service for both newly created and existing clients.
4. Require client-controlled credential setup, verified identity and explicit approval before linking data.
5. Scope every business operation and portal query to the selected organisation.
6. Test wrong-group, wrong-organisation, insufficient-role, unconfirmed-email, duplicate-link, rollback and revocation cases.
7. Verify email delivery and run the full test suite before production use.

**Status:** Code has been committed on `architectural-edits`. This handoff describes the implementation; it does not assert that local Rails tests or email delivery have been verified.
