class AppointmentCharge < ApplicationRecord
  STATUSES = %w[
    active
    voided
  ].freeze

  CHARGE_TYPES = %w[
    appointment
    additional
  ].freeze

  belongs_to :appointment
  belongs_to :patient
  belongs_to :practice
  belongs_to :created_by, class_name: "User", optional: true

  validates :description, :currency, :charged_at, presence: true

  validates :amount_cents,
            numericality: {
              only_integer: true,
              greater_than: 0
            }

  validates :status,
            presence: true,
            inclusion: { in: STATUSES }

  validates :charge_type,
            presence: true,
            inclusion: { in: CHARGE_TYPES }

  validate :appointment_relationships_match

  scope :active, -> { where(status: "active") }

  private

    def appointment_relationships_match
      return if appointment.blank?

      if patient_id.present? && patient_id != appointment.patient_id
        errors.add(
          :patient,
          "must match the appointment patient"
        )
      end

      if practice_id.present? && practice_id != appointment.practice_id
        errors.add(
          :practice,
          "must match the appointment practice"
        )
      end
    end
end
