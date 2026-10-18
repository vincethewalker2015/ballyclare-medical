require "rails_helper"

RSpec.describe Practices::BootstrapSeniorStaffAdmin do
  let(:practice) { create(:practice) }
  let(:user) { create(:user) }

  subject(:bootstrap) do
    described_class.new(practice: practice, user: user)
  end

  it "creates the first senior staff admin in the specified practice" do
    expect { bootstrap.call }.to change(practice.staff_members, :count).by(1)

    staff_member = practice.staff_members.find_by!(user: user)
    expect(staff_member).to have_attributes(
      staff_type: "administrator",
      access_level: "senior_staff_admin",
      active: true
    )
  end

  it "does not bootstrap a practice that already has staff" do
    create(:staff_member, practice: practice)

    expect { bootstrap.call }
      .to raise_error(described_class::AlreadyProvisioned)

    expect(practice.staff_members.where(user: user)).to be_empty
  end

  it "does not create duplicate memberships when called twice" do
    bootstrap.call

    expect { bootstrap.call }
      .to raise_error(described_class::AlreadyProvisioned)

    expect(practice.staff_members.where(user: user).count).to eq(1)
  end

  it "keeps a user's existing memberships in other practices unchanged" do
    other_practice = create(:practice)
    existing_membership = create(
      :staff_member, user: user, practice: other_practice, access_level: "staff"
    )

    bootstrap.call

    expect(existing_membership.reload.access_level).to eq("staff")
    expect(practice.staff_members.find_by!(user: user).access_level)
      .to eq("senior_staff_admin")
  end
  it "allows only one of two concurrent bootstrap attempts", :concurrency do
    second_user = create(:user)
    practice_id = practice.id
    user_ids = [ user.id, second_user.id ]
    ready = Queue.new
    start = Queue.new

    threads = user_ids.map do |user_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop

          begin
            Practices::BootstrapSeniorStaffAdmin.new(
              practice: Practice.find(practice_id),
              user: User.find(user_id)
            ).call
            :created
          rescue Practices::BootstrapSeniorStaffAdmin::AlreadyProvisioned
            :already_provisioned
          end
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)

    expect(results.sort).to eq([ :already_provisioned, :created ])
    expect(practice.staff_members.count).to eq(1)
  end
end
