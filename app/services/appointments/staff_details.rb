module Appointments
  class StaffDetails
    attr_reader :appointment, :refunds_by_status, :balance,
                :allowed_status_transitions, :status_changes, :returned_payment

    def initialize(appointment:, payment_return: nil)
      @appointment = appointment
      @payment_return = payment_return
    end

    def call
      @refunds_by_status = Refund.joins(:payment)
        .where(payments: { appointment_id: appointment.id })
        .order(:created_at).to_a.group_by(&:status)
      @balance = Billing::AppointmentBalance.new(appointment: appointment).call
      @allowed_status_transitions = Appointments::ChangeStatus.allowed_transitions(appointment.status)
      @status_changes = appointment.appointment_status_changes.order(created_at: :desc)
      @returned_payment = appointment.payments.find_by(id: @payment_return) if @payment_return.present?
      self
    end
  end
end
