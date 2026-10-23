require "rails_helper"

RSpec.describe Billing::ConsultationPrice do
  let(:practice) { create(:practice) }
  let(:clinician) { create(:staff_member, practice: practice, staff_type: "doctor") }

  it "returns the configured price for the clinician type" do
    fee = create(:consultation_fee, practice: practice, amount_cents: 7_250)
    expect(described_class.new(practice: practice, clinician: clinician).call).to eq(fee)
  end

  it "refuses to use another practice's fee" do
    create(:consultation_fee, practice: practice)
    clinician.update!(practice: create(:practice))
    expect { described_class.new(practice: practice, clinician: clinician).call }
      .to raise_error(described_class::Unavailable)
  end

  it "fails when a fee has not been configured" do
    expect { described_class.new(practice: practice, clinician: clinician).call }
      .to raise_error(described_class::Unavailable, /not configured/)
  end
end
