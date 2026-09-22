class Payment < ApplicationRecord
  STATUSES = %w[pending processing succeeded failed cancelled].freeze

  belongs_to :appointment
  belongs_to :patient

  has_many :refunds, dependent: :restrict_with_error

  validates :provider, :currency, :idempotency_key, presence: true
  validates :amount_cents,
    numericality: { only_integer: true, greater_than: 0 }

  validates :status,
    presence: true,
    inclusion: { in: STATUSES }

  validates :idempotency_key, uniqueness: true
end
