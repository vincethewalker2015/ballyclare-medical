module PatientPortal
  class Dashboard
    attr_reader :patient, :practice, :next_appointment, :upcoming_appointments,
                :outstanding_appointments, :balances

    def initialize(patient_account:)
      @patient_account = patient_account
    end

    def call
      link = @patient_account.patient_account_links.approved
        .includes(:patient, :practice).first
      return self unless link && link.patient.practice_id == link.practice_id

      @patient = link.patient
      @practice = link.practice
      appointments = practice.appointments.where(patient: patient)
        .includes(:practice, :clinician, :appointment_slot)
      @upcoming_appointments = appointments
        .joins(:appointment_slot)
        .where.not(status: %w[cancelled did_not_attend completed])
        .where("appointment_slots.starts_at >= ?", Time.current)
        .order("appointment_slots.starts_at ASC").limit(5).to_a
      @next_appointment = upcoming_appointments.first

      # Billing is independent of appointment status: completed appointments
      # may still have an outstanding balance.
      billable = appointments.to_a
      @balances = Billing::AppointmentBalances.new(appointments: billable).call
      @outstanding_appointments = billable.select do |appointment|
        balances.fetch(appointment.id)[:balance_cents].positive?
      end.sort_by { |appointment| appointment.appointment_slot.starts_at }.reverse
      self
    end
  end
end
