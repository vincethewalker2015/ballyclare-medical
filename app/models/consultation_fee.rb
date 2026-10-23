class ConsultationFee < ApplicationRecord
  CLINICIAN_TYPES = %w[doctor nurse].freeze

  belongs_to :practice

  validates :clinician_type, inclusion: { in: CLINICIAN_TYPES },
    uniqueness: { scope: :practice_id }
  validates :currency, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validate :currency_matches_practice

  private

  def currency_matches_practice
    return if practice.blank? || currency.blank?
    errors.add(:currency, "must match the practice currency") if currency != practice.currency
  end
end
