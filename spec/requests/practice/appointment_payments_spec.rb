require "rails_helper"

RSpec.describe "Practice appointment payments", type: :request do
  let(:appointment) { create(:appointment) }
  let(:user) { create(:user) }

  before do
    create(
      :staff_member,
      practice: appointment.practice,
      user: user,
      staff_type: "administrator",
      access_level: "staff_admin"
    )

    sign_in user
  end

  describe "GET /practice/appointments/:appointment_id/payment/status" do
    let(:payment) do
      create(:payment,
        appointment: appointment,
        appointment_hold: nil,
        patient: appointment.patient,
        provider: "stripe",
        provider_payment_id: "pi_status_recovery",
        amount_cents: 5000,
        currency: appointment.practice.currency,
        status: "processing")
    end

    before do
      create(:appointment_charge, appointment: appointment,
        patient: appointment.patient, practice: appointment.practice,
        amount_cents: 5000, status: "active")
      payment.update_columns(updated_at: 10.seconds.ago)
    end

    def status_request
      get status_practice_appointment_payment_path(appointment, payment_id: payment.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    it "reconciles a confirmed Stripe success without waiting for a webhook" do
      intent = instance_double(Stripe::PaymentIntent,
        id: "pi_status_recovery",
        status: "succeeded",
        amount_received: 5000,
        currency: appointment.practice.currency.downcase)

      expect(Stripe::PaymentIntent).to receive(:retrieve).with("pi_status_recovery").and_return(intent)

      status_request

      expect(response).to have_http_status(:success)
      expect(payment.reload.status).to eq("succeeded")
      expect(response.body).to include("Payment received")
      expect(Billing::AppointmentBalance.new(appointment: appointment).call[:balance_cents]).to eq(0)
    end

    it "keeps an unconfirmed payment processing without marking it paid" do
      intent = instance_double(Stripe::PaymentIntent,
        id: "pi_status_recovery", status: "requires_action")
      allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)

      status_request

      expect(response).to have_http_status(:no_content)
      expect(payment.reload.status).to eq("processing")
    end

    it "does not mark a payment as paid when Stripe cannot be reached" do
      allow(Stripe::PaymentIntent).to receive(:retrieve)
        .and_raise(Stripe::APIConnectionError.new("Unable to reach Stripe"))

      status_request

      expect(response).to have_http_status(:no_content)
      expect(payment.reload.status).to eq("processing")
    end

    it "does not contact Stripe for a recently updated payment" do
      payment.update_columns(updated_at: Time.current)
      expect(Stripe::PaymentIntent).not_to receive(:retrieve)

      status_request

      expect(response).to have_http_status(:no_content)
    end

    it "reconciles cancellation confirmed by Stripe" do
      intent = instance_double(Stripe::PaymentIntent,
        id: "pi_status_recovery", status: "canceled")
      expect(Stripe::PaymentIntent).to receive(:retrieve).twice
        .with("pi_status_recovery").and_return(intent)

      status_request

      expect(response).to have_http_status(:success)
      expect(payment.reload.status).to eq("cancelled")
      expect(response.body).to include("Payment failed")
    end

    it "does not credit a success with a mismatched amount" do
      intent = instance_double(Stripe::PaymentIntent,
        id: "pi_status_recovery", status: "succeeded",
        amount_received: 4000, currency: appointment.practice.currency.downcase)
      allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)

      expect { status_request }.to raise_error(Payments::HandleSucceeded::AmountMismatch)
      expect(payment.reload.status).to eq("processing")
    end
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
