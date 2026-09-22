class Refund < ApplicationRecord
  STATUSES = %w[pending processing succeeded failed cancelled].freeze

  belongs_to :payment
  belongs_to :requested_by, class_name: "User", optional: true

  validates :amount_cents,
    numericality: { only_integer: true, greater_than: 0 }

  validates :currency, :requested_at, presence: true

  validates :status,
    presence: true,
    inclusion: { in: STATUSES }
end
