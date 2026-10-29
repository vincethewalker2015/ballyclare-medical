module Appointments
  class StaffDiary
    VIEWS = %w[today tomorrow date upcoming past payment_due].freeze

    attr_reader :view, :layout, :clinicians, :clinician_only_diary,
                :selected_clinician_id, :selected_clinician, :date,
                :appointments, :balances

    def initialize(practice:, staff_member:, view:, layout:, clinician_id:, date:)
      @practice = practice
      @staff_member = staff_member
      @view = view.presence_in(VIEWS) || "today"
      @layout = layout.presence_in(%w[board list]) || "board"
      @clinician_id = clinician_id
      @requested_date = date
    end

    def call
      @clinicians = practice.staff_members
        .where(staff_type: %w[doctor nurse], active: true)
        .order(:last_name, :first_name)
      @clinician_only_diary = staff_member.access_level == "staff_clinician"
      @selected_clinician_id = clinician_only_diary ? staff_member.id : @clinician_id.presence
      @selected_clinician = clinicians.find(selected_clinician_id) if selected_clinician_id.present?

      Time.use_zone(practice.timezone) do
        today = Time.zone.today
        @date = diary_date(today)
        @appointments = scoped_appointments(today)
      end

      @balances = Billing::AppointmentBalances.new(appointments: appointments).call
      if view == "payment_due"
        @appointments = appointments.select do |appointment|
          balances.fetch(appointment.id)[:balance_cents].positive?
        end
      end

      self
    end

    private

    attr_reader :practice, :staff_member

    def diary_date(today)
      case view
      when "tomorrow" then today + 1.day
      when "date"
        Date.iso8601(@requested_date.to_s)
      else
        today
      end
    rescue Date::Error
      today
    end

    def scoped_appointments(today)
      relation = practice.appointments
        .includes(:patient, :clinician, :appointment_slot)
        .joins(:appointment_slot)
      relation = relation.where(clinician: selected_clinician) if selected_clinician.present?

      today_start = Time.zone.local(today.year, today.month, today.day)
      selected_start = Time.zone.local(date.year, date.month, date.day)

      case view
      when "upcoming"
        relation.where("appointment_slots.starts_at >= ?", today_start + 1.day)
          .order("appointment_slots.starts_at ASC")
      when "payment_due"
        relation.where(status: %w[booked completed]).order("appointment_slots.starts_at DESC")
      when "past"
        relation.where("appointment_slots.starts_at < ?", today_start)
          .order("appointment_slots.starts_at DESC")
      else
        relation.where(appointment_slots: { starts_at: selected_start...(selected_start + 1.day) })
          .order("appointment_slots.starts_at ASC")
      end
    end
  end
end
