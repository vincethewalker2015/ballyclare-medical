require "rails_helper"

RSpec.describe "Staff unresolved booking payment review", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }

  let!(:membership) do
    create(:staff_member, practice: practice, user: user,
      active: true, access_level: "staff_admin")
  end

  it "shows an actionable Stripe verification form for an eligible unresolved payment" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    payment.update_columns(updated_at: 20.minutes.ago)

    sign_in user
    get practice_booking_payment_reconciliations_path

    expect(response).to have_http_status(:ok)
    form = Nokogiri::HTML(response.body).at_css(
      "form[action='#{verify_practice_booking_payment_reconciliation_path(payment)}'][method='post']"
    )
    expect(form).to be_present
    expect(form.at_css("input[name='payment_intent_id']")).to be_present
    expect(form.at_css("button[type='submit'], input[type='submit']")).to be_present
  end

  it "lists stale unresolved booking payments without Stripe IDs only for the staff member's practice" do
    own_patient = create(:patient, practice: practice)
    other_patient = create(:patient, practice: create(:practice))
    own_payment = create(:payment, appointment: nil, patient: own_patient,
      status: "pending", provider_payment_id: nil)
    foreign_payment = create(:payment, appointment: nil, patient: other_patient,
      status: "pending", provider_payment_id: nil)
    own_payment.update_columns(updated_at: 20.minutes.ago)
    foreign_payment.update_columns(updated_at: 20.minutes.ago)

    sign_in user

    expect {
      get practice_booking_payment_reconciliations_path
    }.not_to change(Payment, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_payment.id.to_s)
    expect(response.body).not_to include(foreign_payment.id.to_s)
    expect(own_payment.reload.status).to eq("pending")
    expect(own_payment.provider_payment_id).to be_nil
  end
  it "includes stale guest booking payments and excludes other practices" do
    make_guest_payment = lambda do |owner_practice|
      slot = create(:appointment_slot, practice: owner_practice)
      guest = GuestBooking.create!(
        practice: owner_practice, appointment_slot: slot,
        first_name: "Guest", last_name: "Visitor",
        date_of_birth: Date.new(1990, 1, 1),
        email: "guest@example.test", phone: "07123456789",
        consultation_reason: "Consultation",
        expires_at: 1.hour.from_now
      )
      payment = create(:payment, appointment: nil, patient: nil,
        guest_booking: guest, status: "processing",
        provider_payment_id: "pi_guest_#{guest.id}")
      payment.update_columns(updated_at: 20.minutes.ago)
      payment
    end

    own_payment = make_guest_payment.call(practice)
    foreign_payment = make_guest_payment.call(create(:practice))

    sign_in user
    get practice_booking_payment_reconciliations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_payment.provider_payment_id)
    expect(response.body).not_to include(foreign_payment.provider_payment_id)
  end

  it "excludes recent and resolved payments from the review queue" do
    patient = create(:patient, practice: practice)
    stale = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    recent = create(:payment, appointment: nil, patient: patient,
      status: "processing", provider_payment_id: "pi_recent_only")
    resolved = create(:payment, appointment: nil, patient: patient,
      status: "failed", provider_payment_id: "pi_resolved_only")
    stale.update_columns(updated_at: 20.minutes.ago)
    resolved.update_columns(updated_at: 20.minutes.ago)

    sign_in user
    get practice_booking_payment_reconciliations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(stale.id.to_s)
    expect(response.body).not_to include("pi_recent_only", "pi_resolved_only")
    expect(recent.reload.status).to eq("processing")
    expect(resolved.reload.status).to eq("failed")
  end

  it "rejects unauthenticated and basic staff access" do
    get practice_booking_payment_reconciliations_path
    expect(response).to redirect_to(new_user_session_path)

    membership.update!(access_level: "staff")
    sign_in user
    get practice_booking_payment_reconciliations_path

    expect(response).to have_http_status(:forbidden)
  end

  it "refuses to reconcile a Stripe intent belonging to another payment" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    payment.update_columns(updated_at: 20.minutes.ago)

    stripe_intent = instance_double(Stripe::PaymentIntent,
      id: "pi_unrelated", status: "succeeded",
      metadata: { "payment_id" => "some-other-payment" },
      amount_received: payment.amount_cents,
      currency: payment.currency.downcase)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_unrelated").and_return(stripe_intent)

    sign_in user

    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_unrelated" }
    }.not_to change(Appointment, :count)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
  end

  it "verifies a matching Stripe reference without marking the payment paid or booking" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_matching", status: "requires_payment_method",
      metadata: { "payment_id" => payment.id.to_s })
    allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_matching").and_return(intent)

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_matching" }
    }.not_to change(Appointment, :count)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
  end

  it "preserves the payment when Stripe verification is unavailable" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_unavailable").and_raise(Stripe::APIConnectionError.new("timeout"))

    sign_in user
    post verify_practice_booking_payment_reconciliation_path(payment),
      params: { payment_intent_id: "pi_unavailable" }

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
  end

  it "forbids basic staff from verifying a payment" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    membership.update!(access_level: "staff")
    sign_in user

    expect(Stripe::PaymentIntent).not_to receive(:retrieve)
    post verify_practice_booking_payment_reconciliation_path(payment),
      params: { payment_intent_id: "pi_forbidden" }

    expect(response).to have_http_status(:forbidden)
    expect(payment.reload.status).to eq("pending")
  end

  it "does not retrieve a Stripe intent for another practice's payment" do
    patient = create(:patient, practice: create(:practice))
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    sign_in user

    expect(Stripe::PaymentIntent).not_to receive(:retrieve)
    post verify_practice_booking_payment_reconciliation_path(payment),
      params: { payment_intent_id: "pi_foreign" }

    expect(response).to have_http_status(:not_found)
    expect(payment.reload.status).to eq("pending")
  end

  it "audits a matching manual Stripe verification without changing the payment" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_audit_matching", status: "requires_payment_method",
      metadata: { "payment_id" => payment.id.to_s })
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_audit_matching").and_return(intent)

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_audit_matching" }
    }.to change {
      AuditEvent.where(practice: practice, auditable: payment,
        user: user, action: "stripe_payment.verification_matched").count
    }.by(1)

    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
  end

  it "audits a Stripe reference rejected for mismatched payment metadata" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_wrong_owner", status: "succeeded",
      metadata: { "payment_id" => "another-payment" })
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_wrong_owner").and_return(intent)

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_wrong_owner" }
    }.to change {
      AuditEvent.where(practice: practice, auditable: payment,
        user: user, action: "stripe_payment.verification_rejected").count
    }.by(1)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
  end

  it "audits unavailable Stripe verification without changing the payment" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, appointment: nil, patient: patient,
      status: "pending", provider_payment_id: nil)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_audit_unavailable")
      .and_raise(Stripe::APIConnectionError.new("timeout"))

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_audit_unavailable" }
    }.to change {
      AuditEvent.where(practice: practice, auditable: payment,
        user: user, action: "stripe_payment.verification_unavailable").count
    }.by(1)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
  end

  it "recovers a verified successful Stripe payment without initiating a new charge" do
    slot = create(:appointment_slot, practice: practice)
    patient = create(:patient, practice: practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      amount_cents: 6500, currency: practice.currency,
      status: "pending", idempotency_key: SecureRandom.uuid
    )
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_manual_recovery", status: "succeeded",
      metadata: { "payment_id" => payment.id.to_s },
      amount_received: payment.amount_cents,
      currency: payment.currency.downcase)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_manual_recovery").and_return(intent)
    expect(Stripe::PaymentIntent).not_to receive(:create)

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_manual_recovery" }
    }.to change(Appointment, :count).by(1)
      .and change(AppointmentCharge, :count).by(1)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("succeeded")
    expect(payment.provider_payment_id).to eq("pi_manual_recovery")
    expect(payment.appointment).to be_present
    expect(AuditEvent.where(practice: practice, auditable: payment,
      user: user, action: "stripe_payment.recovered").count).to eq(1)
  end

  it "requires a refund instead of booking when manual recovery finds an expired hold" do
    slot = create(:appointment_slot, practice: practice)
    patient = create(:patient, practice: practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      amount_cents: 6500, currency: practice.currency,
      status: "pending", idempotency_key: SecureRandom.uuid
    )
    hold.update!(expires_at: 1.minute.ago)
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_expired_manual_recovery", status: "succeeded",
      metadata: { "payment_id" => payment.id.to_s },
      amount_received: payment.amount_cents,
      currency: payment.currency.downcase)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_expired_manual_recovery").and_return(intent)
    expect(Stripe::PaymentIntent).not_to receive(:create)

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_expired_manual_recovery" }
    }.not_to change(Appointment, :count)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("requires_refund")
    expect(payment.provider_payment_id).to eq("pi_expired_manual_recovery")
    expect(AuditEvent.where(practice: practice, auditable: payment,
      user: user, action: "stripe_payment.recovered").count).to eq(1)
  end

  it "rejects manual recovery when Stripe reports an incorrect received amount" do
    slot = create(:appointment_slot, practice: practice)
    patient = create(:patient, practice: practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      amount_cents: 6500, currency: practice.currency,
      status: "pending", idempotency_key: SecureRandom.uuid
    )
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_wrong_recovery_amount", status: "succeeded",
      metadata: { "payment_id" => payment.id.to_s },
      amount_received: 6400, currency: payment.currency.downcase)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_wrong_recovery_amount").and_return(intent)
    expect(Stripe::PaymentIntent).not_to receive(:create)

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_wrong_recovery_amount" }
    }.not_to change(Appointment, :count)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
    expect(AppointmentCharge.where(appointment_id: payment.appointment_id).count).to eq(0)
  end

  it "rejects manual recovery when Stripe reports an incorrect currency" do
    slot = create(:appointment_slot, practice: practice)
    patient = create(:patient, practice: practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      amount_cents: 6500, currency: practice.currency,
      status: "pending", idempotency_key: SecureRandom.uuid
    )
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_wrong_recovery_currency", status: "succeeded",
      metadata: { "payment_id" => payment.id.to_s },
      amount_received: payment.amount_cents, currency: "eur")
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_wrong_recovery_currency").and_return(intent)
    expect(Stripe::PaymentIntent).not_to receive(:create)

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_wrong_recovery_currency" }
    }.not_to change(Appointment, :count)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("pending")
    expect(payment.provider_payment_id).to be_nil
    expect(AuditEvent.where(practice: practice, auditable: payment,
      user: user, action: "stripe_payment.verification_rejected").count).to eq(1)
  end

  it "does not duplicate the appointment or charge when successful recovery is submitted twice" do
    slot = create(:appointment_slot, practice: practice)
    patient = create(:patient, practice: practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      amount_cents: 6500, currency: practice.currency,
      status: "pending", idempotency_key: SecureRandom.uuid
    )
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_recovery_twice", status: "succeeded",
      metadata: { "payment_id" => payment.id.to_s },
      amount_received: payment.amount_cents,
      currency: payment.currency.downcase)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_recovery_twice").and_return(intent)
    expect(Stripe::PaymentIntent).not_to receive(:create)

    sign_in user
    post verify_practice_booking_payment_reconciliation_path(payment),
      params: { payment_intent_id: "pi_recovery_twice" }
    expect(payment.reload.status).to eq("succeeded")
    original_appointment_id = payment.appointment_id

    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_recovery_twice" }
    }.not_to change(Appointment, :count)
    expect(AppointmentCharge.where(appointment_id: original_appointment_id).count).to eq(1)
    expect(payment.reload.appointment_id).to eq(original_appointment_id)
    expect(AuditEvent.where(practice: practice, auditable: payment,
      user: user, action: "stripe_payment.recovered").count).to eq(1)
  end

  it "does not duplicate booking when a successful webhook is handled during manual Stripe verification" do
    slot = create(:appointment_slot, practice: practice)
    patient = create(:patient, practice: practice)
    hold = slot.hold_for!(patient: patient)
    payment = Payment.create!(
      appointment_hold: hold, patient: patient, provider: "stripe",
      amount_cents: 6500, currency: practice.currency,
      status: "pending", idempotency_key: SecureRandom.uuid
    )
    intent = instance_double(Stripe::PaymentIntent,
      id: "pi_webhook_during_verification", status: "succeeded",
      metadata: { "payment_id" => payment.id.to_s },
      amount_received: payment.amount_cents,
      currency: payment.currency.downcase)
    allow(Stripe::PaymentIntent).to receive(:retrieve)
      .with("pi_webhook_during_verification") do
        Payments::HandleSucceeded.new(payment_intent: intent).call
        intent
      end
    expect(Stripe::PaymentIntent).not_to receive(:create)

    sign_in user
    expect {
      post verify_practice_booking_payment_reconciliation_path(payment),
        params: { payment_intent_id: "pi_webhook_during_verification" }
    }.to change(Appointment, :count).by(1)
      .and change(AppointmentCharge, :count).by(1)

    expect(response).to redirect_to(practice_booking_payment_reconciliations_path)
    expect(payment.reload.status).to eq("succeeded")
    expect(payment.provider_payment_id).to eq("pi_webhook_during_verification")
    expect(payment.appointment.appointment_charges.count).to eq(1)
  end

end
