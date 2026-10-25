module Booking
  class StaffBookingOptions
    attr_reader :fees_by_type, :booking_date, :selected_patient, :clinicians

    def initialize(practice:, patient_id: nil)
      @practice = practice
      @patient_id = patient_id
    end

    def call
      @fees_by_type = @practice.consultation_fees.index_by(&:clinician_type)
      @booking_date = Time.use_zone(@practice.timezone) { Time.zone.today }
      @selected_patient = @practice.patients.find_by(id: @patient_id) if @patient_id.present?
      @clinicians = @practice.staff_members
        .where(staff_type: %w[doctor nurse])
        .order(:last_name, :first_name)
      self
    end
  end
end
