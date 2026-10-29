module Staff
  class AppointmentsController < BaseController
    before_action :require_operational_access, except: %i[index show]
    def index
      @practice = current_practice
      diary = Appointments::StaffDiary.new(
        practice: current_practice, staff_member: current_staff_member,
        view: params[:view], layout: params[:layout],
        clinician_id: params[:clinician_id], date: params[:date]
      ).call

      @diary_view = diary.view
      @diary_layout = diary.layout
      @clinicians = diary.clinicians
      @clinician_only_diary = diary.clinician_only_diary
      @selected_clinician_id = diary.selected_clinician_id
      @selected_clinician = diary.selected_clinician
      @diary_date = diary.date
      @appointments = diary.appointments
      @appointment_balances = diary.balances
    end

    def show
      @appointment = current_practice
        .appointments
        .includes(
          :patient,
          :clinician,
          :appointment_slot,
          :appointment_charges,
          :payments,
          appointment_status_changes: :changed_by
        )
        .find(params[:id])

      if current_staff_member.access_level == "staff_clinician" && @appointment.clinician_id != current_staff_member.id
        return head :forbidden
      end

      details = Appointments::StaffDetails.new(
        appointment: @appointment, payment_return: params[:payment_return]
      ).call
      @refunds_by_status = details.refunds_by_status
      @balance = details.balance
      @allowed_status_transitions = details.allowed_status_transitions
      @status_changes = details.status_changes
      @returned_payment = details.returned_payment
    end

    def new
      load_booking_options
    end

    def create
      if params[:patient_id].blank? ||
         params[:appointment_slot_id].blank?
        return render_booking_error(
          "Select a patient, clinician and available appointment."
        )
      end

      patient = current_practice
        .patients
        .find(params[:patient_id])

      appointment_slot = current_practice
        .appointment_slots
        .find(params[:appointment_slot_id])

      appointment = Booking::CreateStaffAppointment.new(
        appointment_slot: appointment_slot,
        patient: patient,
        booked_by: current_user,
        reason: params[:reason].presence
      ).call

      redirect_to practice_appointment_path(appointment),
                  notice: "Appointment booked successfully."
    rescue Billing::ConsultationPrice::Unavailable => error
      render_booking_error(error.message)
    rescue Booking::CreateStaffAppointment::SlotUnavailable
      render_booking_error(
        "That appointment is no longer available. Please choose another time."
      )
    end

    def search_patients
      render json: Appointments::SearchStaffPatients.new(
        practice: current_practice, term: params[:q]
      ).call
    end

    def available_slots
      @clinician = current_practice
        .staff_members
        .where(staff_type: %w[doctor nurse], active: true)
        .find(params[:clinician_id])

      @appointment_slots = Appointments::AvailableStaffSlots.new(
        practice: current_practice, clinician: @clinician, date: params[:date]
      ).call

      render turbo_stream: turbo_stream.replace(
        "available_appointment_slots",
        partial: "staff/appointments/available_slots",
        locals: {
          appointment_slots: @appointment_slots,
          practice_timezone: current_practice.timezone
        }
      )
    end

    def status
      appointment = current_practice.appointments.find(params[:id])

      Appointments::ChangeStatus.new(
        appointment: appointment,
        to_status: params[:status],
        changed_by: current_user
      ).call

      details = Appointments::StaffDetails.new(appointment: appointment).call
      allowed_status_transitions = details.allowed_status_transitions
      status_changes = appointment.appointment_status_changes
        .includes(:changed_by).order(created_at: :desc)
      balance = details.balance

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "appointment_status_badge",
              partial: "staff/appointments/status_badge",
              locals: {
                appointment: appointment
              }
            ),
            turbo_stream.replace(
              "appointment_lifecycle_controls",
              partial: "staff/appointments/lifecycle_controls",
              locals: {
                appointment: appointment,
                allowed_status_transitions: allowed_status_transitions
              }
            ),
            turbo_stream.replace(
              "appointment_activity",
              partial: "staff/appointments/activity",
              locals: {
                appointment: appointment,
                status_changes: status_changes
              }
            ),
            turbo_stream.replace(
              "financial_summary",
              partial: "staff/appointments/financial_summary",
              locals: {
                appointment: appointment,
                balance: balance
              }
            ),
            turbo_stream.replace(
              "appointment_charges",
              partial: "staff/appointments/charges",
              locals: {
                appointment: appointment
              }
            )
          ]
        end

        format.html do
          redirect_to practice_appointment_path(appointment),
                      notice: "Appointment status updated."
        end
      end
    rescue Appointments::ChangeStatus::InvalidTransition,
       Appointments::ChangeStatus::PaymentInProgress => error
      redirect_to practice_appointment_path(appointment),
                  alert: error.message
    end

    private

    def load_booking_options
      options = Booking::StaffBookingOptions.new(
        practice: current_practice, patient_id: params[:patient_id]
      ).call
      @fees_by_type = options.fees_by_type
      @booking_date = options.booking_date
      @selected_patient = options.selected_patient
      @clinicians = options.clinicians
    end

    def render_booking_error(message)
      load_booking_options

      flash.now[:alert] = message

      render :new, status: :unprocessable_content
    end
  end
end
