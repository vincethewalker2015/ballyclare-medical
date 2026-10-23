module Billing
  class ConsultationPrice
    class Unavailable < StandardError; end

    def initialize(practice:, clinician:)
      @practice = practice
      @clinician = clinician
    end

    def call
      unless clinician.practice_id == practice.id &&
             clinician.staff_type.in?(ConsultationFee::CLINICIAN_TYPES) &&
             clinician.active?
        raise Unavailable, "Clinician is not available for consultation pricing"
      end

      fee = practice.consultation_fees.find_by(clinician_type: clinician.staff_type)
      raise Unavailable, "Consultation fee is not configured" unless fee
      raise Unavailable, "Consultation fee currency does not match the practice" unless fee.currency == practice.currency

      fee
    end

    private

    attr_reader :practice, :clinician
  end
end
