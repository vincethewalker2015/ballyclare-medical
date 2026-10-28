require "rails_helper"
require "active_support/testing/time_helpers"


RSpec.describe Payments::StripeOutageDeclaration do
  include ActiveSupport::Testing::TimeHelpers
  let(:practice) { create(:practice) }
  let(:administrator) do
    create(:staff_member, practice: practice, staff_type: "administrator",
      access_level: "senior_staff_admin")
  end

  it "defaults to inactive without an authorized declaration" do
    expect(described_class.active?(practice: practice)).to be(false)
  end

  it "records a time-limited, auditable declaration by a senior administrator" do
    travel_to Time.zone.parse("2026-10-28 12:00:00") do
      expect {
        described_class.activate!(practice: practice, actor: administrator,
          reason: "Stripe status page confirms a service outage")
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(event.practice).to eq(practice)
      expect(event.user).to eq(administrator.user)
      expect(event.action).to eq("stripe_outage.activated")
      expect(event.metadata["reason"]).to eq("Stripe status page confirms a service outage")
      expect(described_class.active?(practice: practice)).to be(true)

      travel 31.minutes
      expect(described_class.active?(practice: practice)).to be(false)
    end
  end

  it "rejects activation by a non-senior staff member" do
    ordinary_staff = create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "staff_admin")

    expect {
      described_class.activate!(practice: practice, actor: ordinary_staff,
        reason: "Outage confirmed")
    }.to raise_error(Payments::StripeOutageDeclaration::Unauthorized)

    expect(described_class.active?(practice: practice)).to be(false)
  end

  it "does not allow an administrator from another practice to activate the outage" do
    other_practice = create(:practice)

    expect {
      described_class.activate!(practice: other_practice, actor: administrator,
        reason: "Outage confirmed")
    }.to raise_error(Payments::StripeOutageDeclaration::Unauthorized)
  end

  it "allows a senior administrator to deactivate an active declaration" do
    described_class.activate!(practice: practice, actor: administrator,
      reason: "Outage confirmed")
    described_class.deactivate!(practice: practice, actor: administrator,
      reason: "Stripe service restored")

    expect(described_class.active?(practice: practice)).to be(false)
    expect(AuditEvent.order(:created_at).last.action).to eq("stripe_outage.deactivated")
  end

  it "keeps declarations isolated between practices" do
    described_class.activate!(practice: practice, actor: administrator,
      reason: "Outage confirmed")

    expect(described_class.active?(practice: create(:practice))).to be(false)
  end

  it "rejects a blank activation reason without writing an audit event" do
    expect {
      described_class.activate!(practice: practice, actor: administrator, reason: "  ")
    }.to raise_error(Payments::StripeOutageDeclaration::InvalidReason)

    expect(AuditEvent.where(practice: practice, action: "stripe_outage.activated")).to be_empty
  end

  it "does not let a repeated activation silently extend an active declaration" do
    travel_to Time.zone.parse("2026-10-28 12:00:00") do
      described_class.activate!(practice: practice, actor: administrator,
        reason: "Stripe outage confirmed")

      travel 20.minutes
      expect {
        described_class.activate!(practice: practice, actor: administrator,
          reason: "Another report of the same outage")
      }.to raise_error(Payments::StripeOutageDeclaration::AlreadyActive)

      expect(AuditEvent.where(practice: practice, action: "stripe_outage.activated").count).to eq(1)
      travel 11.minutes
      expect(described_class.active?(practice: practice)).to be(false)
    end
  end

  it "rejects deactivation by staff without senior administration access" do
    ordinary_staff = create(:staff_member, practice: practice,
      staff_type: "administrator", access_level: "staff_admin")
    described_class.activate!(practice: practice, actor: administrator,
      reason: "Stripe outage confirmed")

    expect {
      described_class.deactivate!(practice: practice, actor: ordinary_staff,
        reason: "Stripe service restored")
    }.to raise_error(Payments::StripeOutageDeclaration::Unauthorized)

    expect(described_class.active?(practice: practice)).to be(true)
  end

  it "accepts only one of two simultaneous activations", :concurrency do
    practice
    administrator

    ready = Queue.new
    start = Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            described_class.activate!(practice: practice, actor: administrator,
              reason: "Stripe outage confirmed")
            :activated
          rescue described_class::AlreadyActive
            :already_active
          end
        end
      end
    end

    begin
      2.times { ready.pop }
      2.times { start << true }
      expect(workers.map(&:value).sort).to eq(%i[activated already_active].sort)
    ensure
      workers.each { |worker| worker.kill if worker.alive? }
      workers.each(&:join)
    end

    expect(AuditEvent.where(practice: practice, action: "stripe_outage.activated").count).to eq(1)
    expect(described_class.active?(practice: practice)).to be(true)
  end
end
