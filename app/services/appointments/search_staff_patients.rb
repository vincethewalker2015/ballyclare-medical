module Appointments
  class SearchStaffPatients
    def initialize(practice:, term:)
      @practice = practice
      @term = term.to_s.strip
    end

    def call
      patients = @practice.patients.order(:last_name, :first_name, :id)
      if @term.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@term)}%"
        patients = patients.where(
          "first_name ILIKE :term OR last_name ILIKE :term OR patient_number ILIKE :term OR CONCAT(first_name, ' ', last_name) ILIKE :term OR CONCAT(last_name, ', ', first_name) ILIKE :term",
          term: pattern
        )
      end

      patients.limit(5).map do |patient|
        { id: patient.id, label: "#{patient.last_name}, #{patient.first_name} — #{patient.patient_number}" }
      end
    end
  end
end
