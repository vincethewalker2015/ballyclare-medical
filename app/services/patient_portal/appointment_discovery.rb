module PatientPortal
  class AppointmentDiscovery
    attr_reader :patient, :practice, :clinicians, :clinician, :slots

    def initialize(patient_account:, clinician_id: nil, date: nil)
      @patient_account, @clinician_id, @date = patient_account, clinician_id, date
    end

    def call
      link = @patient_account.patient_account_links.approved.includes(:patient, :practice).first
      return self unless link && link.patient.practice_id == link.practice_id

      @patient, @practice = link.patient, link.practice
      @clinicians = practice.staff_members
        .where(staff_type: %w[doctor nurse], active: true)
        .where(id: practice.availability_blocks.active.where(bookable_online: true).select(:clinician_id))
        .order(:last_name, :first_name).to_a
      @clinician = clinicians.find { |candidate| candidate.id.to_s == @clinician_id.to_s } if @clinician_id.present?
      @slots = @clinician ? Appointments::AvailableSlots.new(
        practice: practice, clinician: clinician, date: @date, online_only: true
      ).call.to_a : []
      self
    end
  end
end
