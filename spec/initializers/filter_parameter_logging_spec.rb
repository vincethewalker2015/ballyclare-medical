require "rails_helper"

RSpec.describe "Sensitive parameter logging" do
  it "redacts guest identity, contact details and consultation information" do
    params = ActionController::Parameters.new(
      guest_booking: {
        first_name: "PrivateFirst", last_name: "PrivateLast",
        email: "private@example.com", phone: "07700900999",
        date_of_birth: "1990-01-01",
        consultation_reason: "Private consultation details"
      },
      appointment_slot_id: "slot-123"
    )

    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params.to_unsafe_h)
    details = filtered.fetch("guest_booking")

    %w[first_name last_name email phone date_of_birth consultation_reason].each do |key|
      expect(details.fetch(key)).to eq("[FILTERED]")
    end
    expect(filtered.fetch("appointment_slot_id")).to eq("slot-123")
  end
end
