module PatientPortal
  class AppointmentHistoryController < BaseController
    def index
      link = current_patient_account.patient_account_links.approved
        .includes(:patient, :practice).first
      return head :forbidden unless link && link.patient.practice_id == link.practice_id

      @practice = link.practice
      appointments = @practice.appointments.where(patient_id: link.patient_id)
        .joins(:appointment_slot).includes(:clinician, :appointment_slot)
      @upcoming_appointments = appointments
        .where.not(status: %w[cancelled completed did_not_attend referred])
        .where("appointment_slots.starts_at >= ?", Time.current)
        .order("appointment_slots.starts_at ASC").to_a
      @past_appointments = appointments
        .where("appointment_slots.starts_at < ? OR appointments.status IN (?)",
          Time.current, %w[cancelled completed did_not_attend referred])
        .order("appointment_slots.starts_at DESC").to_a
    end
  end
end
