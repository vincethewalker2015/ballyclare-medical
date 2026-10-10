require "rails_helper"

RSpec.describe "Practice appointment payments", type: :request do
  let(:appointment) { create(:appointment) }
  let(:user) { create(:user) }

  before do
    create(
      :staff_member,
      practice: appointment.practice,
      user: user,
      staff_type: "administrator"
    )

    sign_in user
  end

  describe "POST /practice/appointments/:appointment_id/payment" do
    context "when the appointment is cancelled" do
      before do
        appointment.update!(status: "cancelled")
      end

      it "rejects the payment without contacting Stripe" do
        expect(
          Payments::TakeAppointmentPayment
        ).not_to receive(:new)

        expect do
          post practice_appointment_payment_path(appointment),
               params: { amount: "50.00" }
        end.not_to change(Payment, :count)

        expect(response).to redirect_to(
          practice_appointment_path(appointment)
        )

        expect(flash[:alert]).to eq(
          "Cannot take payment for a cancelled appointment."
        )
      end
    end
  end

  describe "GET /practice/appointments/:appointment_id/payment/new" do
    context "when the appointment is cancelled" do
      before do
        appointment.update!(status: "cancelled")
      end

      it "redirects back to the appointment with an error" do
        get new_practice_appointment_payment_path(appointment)

        expect(response).to redirect_to(
          practice_appointment_path(appointment)
        )

        expect(flash[:alert]).to eq(
          "Cannot take payment for a cancelled appointment."
        )
      end
    end
  end
end
