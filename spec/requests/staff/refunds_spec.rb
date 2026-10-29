require "rails_helper"

RSpec.describe "Staff refund review", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:membership) do
    create(:staff_member, practice: practice, user: user,
      active: true, access_level: "staff_admin")
  end

  def refund_for(patient:, status:)
    payment = create(:payment,
      patient: patient, appointment: nil, guest_booking: nil,
      status: "requires_refund", provider: "stripe")
    create(:refund, payment: payment, status: status)
  end

  it "requires staff authentication" do
    get practice_refunds_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows own-practice refunds including failed exceptions without changing them" do
    own_patient = create(:patient, practice: practice)
    other_patient = create(:patient, practice: create(:practice))
    failed = refund_for(patient: own_patient, status: "failed")
    succeeded = refund_for(patient: own_patient, status: "succeeded")
    foreign = refund_for(patient: other_patient, status: "failed")

    sign_in user
    expect { get practice_refunds_path }.not_to change(Refund, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(failed.id, succeeded.id)
    expect(response.body).not_to include(foreign.id)
    expect(response.body).to include("failed", "succeeded")
    expect(failed.reload.status).to eq("failed")
  end

  it "includes guest refunds only from this practice" do
    make_guest_refund = lambda do |owner_practice|
      slot = create(:appointment_slot, practice: owner_practice)
      booking = GuestBooking.create!(
        practice: owner_practice, appointment_slot: slot,
        first_name: "Guest", last_name: "Patient",
        date_of_birth: Date.new(1990, 1, 1),
        email: "guest@example.test", phone: "07123456789",
        consultation_reason: "Routine consultation",
        expires_at: 1.hour.from_now
      )
      payment = create(:payment,
        appointment: nil, patient: nil, guest_booking: booking,
        status: "requires_refund")
      create(:refund, payment: payment, status: "failed")
    end

    own_refund = make_guest_refund.call(practice)
    foreign_refund = make_guest_refund.call(create(:practice))

    sign_in user
    get practice_refunds_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_refund.id)
    expect(response.body).not_to include(foreign_refund.id)
    expect(response.body).to include("Manual review required")
  end

  it "includes appointment-linked refunds only from this practice" do
    own_appointment = create(:appointment, practice: practice)
    foreign_appointment = create(:appointment, practice: create(:practice))

    own_payment = create(:payment,
      appointment: own_appointment, patient: own_appointment.patient,
      status: "succeeded")
    foreign_payment = create(:payment,
      appointment: foreign_appointment, patient: foreign_appointment.patient,
      status: "succeeded")
    own_refund = create(:refund, payment: own_payment, status: "succeeded")
    foreign_refund = create(:refund, payment: foreign_payment, status: "succeeded")

    sign_in user
    get practice_refunds_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_refund.id)
    expect(response.body).not_to include(foreign_refund.id)
  end

  it "reconciles an older processing refund with Stripe when staff refreshes" do
    patient = create(:patient, practice: practice)
    payment = create(:payment, patient: patient, appointment: nil,
      status: "succeeded", provider_payment_id: "pi_refund_review")
    refund = create(:refund, payment: payment, status: "processing",
      provider_refund_id: "re_refund_review")
    refund.update_columns(updated_at: 1.minute.ago)
    stripe_refund = Stripe::Refund.construct_from(
      id: "re_refund_review", object: "refund",
      amount: refund.amount_cents, currency: refund.currency.downcase,
      status: "succeeded", payment_intent: "pi_refund_review"
    )
    expect(Stripe::Refund).to receive(:retrieve).with("re_refund_review").and_return(stripe_refund)

    sign_in user
    get practice_refunds_path

    expect(response).to have_http_status(:ok)
    expect(refund.reload.status).to eq("succeeded")
    expect(response.body).to include("Completed")
  end

  it "does not allow basic staff to review refunds" do
    membership.update!(access_level: "staff")
    sign_in user

    get practice_refunds_path

    expect(response).to have_http_status(:forbidden)
  end
end
