require "rails_helper"

RSpec.describe "Practice operational permissions", type: :request do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }
  let!(:membership) do
    create(:staff_member, practice: practice, user: user,
      staff_type: "administrator", access_level: "staff")
  end

  before { sign_in user }

  shared_examples "protected operational endpoint" do |path|
    it "forbids basic staff" do
      get public_send(path)
      expect(response).to have_http_status(:forbidden)
    end

    %w[staff_admin senior_staff_admin].each do |level|
      it "allows #{level}" do
        membership.update!(access_level: level)
        get public_send(path)
        expect(response).to have_http_status(:success)
      end
    end

    it "allows staff clinicians" do
      membership.update!(staff_type: "doctor", access_level: "staff_clinician")
      get public_send(path)
      expect(response).to have_http_status(:success)
    end
  end

  include_examples "protected operational endpoint", :practice_appointments_path
  include_examples "protected operational endpoint", :practice_patients_path
  include_examples "protected operational endpoint", :practice_availability_blocks_path

  it "blocks basic staff from appointment creation and financial actions before loading records" do
    get new_practice_appointment_path
    expect(response).to have_http_status(:forbidden)

    get new_practice_appointment_charge_path(0)
    expect(response).to have_http_status(:forbidden)

    get new_practice_appointment_payment_path(0)
    expect(response).to have_http_status(:forbidden)
  end

  it "continues to allow basic staff to view the staff directory" do
    get practice_staff_members_path
    expect(response).to have_http_status(:success)
  end
end
