require "rails_helper"

RSpec.describe Payments::StripeOutageMonitor do
  include ActiveSupport::Testing::TimeHelpers
  let(:practice) { create(:practice) }
  let!(:senior) { create(:staff_member, practice: practice, access_level: "senior_staff_admin") }
  let(:timeout) { Stripe::APIConnectionError.new("Connection timed out") }

  def payment_at(practice)
    create(:payment, appointment: create(:appointment, practice: practice))
  end

  def fail_payment(payment, error: timeout)
    described_class.record_failure(payment: payment, error: error, source: "payment_intent_create")
  end

  it "warns once for three distinct failed payments without activating emergency booking" do
    payments = Array.new(3) { payment_at(practice) }

    expect {
      expect(fail_payment(payments[0])).to be(false)
      expect(fail_payment(payments[1])).to be(false)
      expect(fail_payment(payments[2])).to be(true)
    }.to have_enqueued_job(ActionMailer::MailDeliveryJob).exactly(:once)

    expect(AuditEvent.where(practice: practice,
      action: described_class::FAILURE_ACTION).count).to eq(3)
    expect(AuditEvent.where(practice: practice,
      action: described_class::SUSPECTED_ACTION).count).to eq(1)
    expect(Payments::StripeOutageDeclaration.active?(practice: practice)).to be(false)
    expect(described_class.suspected_event(practice: practice)).to be_present
  end

  it "deduplicates repeated failures for the same payment and suppresses repeated alerts" do
    payment = payment_at(practice)
    5.times { fail_payment(payment) }
    expect(AuditEvent.where(practice: practice,
      action: described_class::FAILURE_ACTION).count).to eq(1)
    expect(described_class.suspected_event(practice: practice)).to be_nil

    2.times { fail_payment(payment_at(practice)) }
    expect(AuditEvent.where(practice: practice,
      action: described_class::SUSPECTED_ACTION).count).to eq(1)

    expect {
      fail_payment(payment_at(practice))
    }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
  end

  it "does not combine failures across practices, even in the same medical group" do
    sibling_practice = create(:practice, medical_group: practice.medical_group)
    2.times { fail_payment(payment_at(practice)) }
    fail_payment(payment_at(sibling_practice))

    expect(AuditEvent.where(action: described_class::SUSPECTED_ACTION)).to be_empty
    expect(described_class.suspected_event(practice: sibling_practice)).to be_nil
  end

  it "does not combine failures across medical groups" do
    other_practice = create(:practice)
    2.times { fail_payment(payment_at(practice)) }
    fail_payment(payment_at(other_practice))

    expect(AuditEvent.where(action: described_class::SUSPECTED_ACTION)).to be_empty
  end

  it "expires the warning and permits a new alert after the cooldown" do
    3.times { fail_payment(payment_at(practice)) }
    expect(described_class.suspected_event(practice: practice)).to be_present

    travel 31.minutes
    expect(described_class.suspected_event(practice: practice)).to be_nil

    expect {
      3.times { fail_payment(payment_at(practice)) }
    }.to have_enqueued_job(ActionMailer::MailDeliveryJob).exactly(:once)
    expect(AuditEvent.where(practice: practice,
      action: described_class::SUSPECTED_ACTION).count).to eq(2)
  end

  it "does not notify from a card decline or an existing declared outage" do
    payment = payment_at(practice)
    decline = Stripe::CardError.new("Declined", "card_declined")
    expect(fail_payment(payment, error: decline)).to be_nil

    Payments::StripeOutageDeclaration.activate!(
      practice: practice, actor: senior, reason: "Stripe confirmed unavailable"
    )
    expect {
      3.times { fail_payment(payment_at(practice)) }
    }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)

    expect(AuditEvent.where(practice: practice,
      action: described_class::SUSPECTED_ACTION)).to be_empty
  end

  it "excludes old failure signals from the current detection window" do
    2.times do
      payment = payment_at(practice)
      fail_payment(payment)
    end
    AuditEvent.where(practice: practice, action: described_class::FAILURE_ACTION)
      .update_all(created_at: 6.minutes.ago)

    expect(fail_payment(payment_at(practice))).to be(false)
    expect(AuditEvent.where(action: described_class::SUSPECTED_ACTION)).to be_empty
  end

  it "uses only authorized group administrators as email recipients" do
    sibling = create(:practice, medical_group: practice.medical_group)
    sibling_senior = create(:staff_member, practice: sibling,
      access_level: "senior_staff_admin")
    outsider = create(:staff_member, practice: create(:practice),
      access_level: "senior_staff_admin")

    mail = StripeOutageAlertMailer.suspected(practice: practice)
    expect(mail.to).to contain_exactly(senior.user.email, sibling_senior.user.email)
    expect(mail.to).not_to include(outsider.user.email)
    expect(mail.body.encoded).to include(practice.name, "NOT been activated")
    expect(mail.body.encoded).not_to include("payment_id")
  end
end
