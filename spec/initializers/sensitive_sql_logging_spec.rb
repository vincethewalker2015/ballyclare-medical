require "rails_helper"

RSpec.describe "Sensitive SQL logging" do
  it "does not write SQL queries and patient bind values to the Rails logger" do
    expect(ActiveRecord::Base.logger).to be_nil
  end
end
