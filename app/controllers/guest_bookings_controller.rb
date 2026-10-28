class GuestBookingsController < ApplicationController
  layout "public"

  def new
    @slot = public_slot_scope.find(params.require(:appointment_slot_id))
    @guest_booking = GuestBooking.new(
      practice: @slot.practice,
      appointment_slot: @slot,
      expires_at: 30.minutes.from_now
    )
  end

  def create
    @slot = public_slot_scope.find(params.require(:guest_booking).require(:appointment_slot_id))
    @guest_booking = GuestBooking.new(guest_booking_params.except(:appointment_slot_id).merge(
      practice: @slot.practice,
      appointment_slot: @slot,
      expires_at: 30.minutes.from_now
    ))

    if @guest_booking.save
      session[:guest_booking_id] = @guest_booking.id
      redirect_to guest_booking_review_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def review
    @guest_booking = session_guest_booking
    existing_payment = @guest_booking.payment || @guest_booking.appointment_hold&.payments&.first
    @payment_verification_pending = existing_payment&.status.in?(%w[pending processing])
    @emergency_unpaid_available = Payments::EmergencyUnpaidBookingPolicy.new(
      practice: @guest_booking.practice,
      payment: existing_payment
    ).allowed?
  end

  def checkout
    guest = session_guest_booking
    if Payments::StripeOutageDeclaration.active?(practice: guest.practice)
      return redirect_to guest_booking_review_path, alert: "Secure payment is temporarily unavailable. Please review your booking options."
    end

    existing_payment = guest.payment || guest.appointment_hold&.payments&.order(:created_at)&.first
    if existing_payment&.status.in?(%w[pending processing])
      return redirect_to guest_booking_review_path,
        alert: "Payment verification pending. Please wait for your previous payment attempt to be reconciled."
    end

    hold = guest.appointment_hold || GuestBookings::ReserveSlot.new(guest_booking: guest).call
    result = Payments::TakeHoldPayment.new(hold: hold).call
    @payment = result.payment
    @client_secret = result.payment_intent.client_secret
  rescue GuestBookings::ReserveSlot::Unavailable, AppointmentSlot::Unavailable,
         Payments::CreateForHold::HoldExpired, Payments::CreateForHold::PaymentInProgress,
         Billing::ConsultationPrice::Unavailable
    redirect_to guest_booking_review_path, alert: "This appointment is no longer available for checkout."
  rescue Stripe::StripeError
    redirect_to guest_booking_review_path, alert: "Secure payment could not be started. Please try again."
  end

  def emergency_unpaid
    guest = session_guest_booking
    hold = guest.appointment_hold || GuestBookings::ReserveSlot.new(guest_booking: guest).call
    appointment = GuestBookings::CompleteEmergencyUnpaidBooking.new(hold: hold).call
    session[:guest_emergency_appointment_id] = appointment.id
    redirect_to guest_booking_emergency_confirmation_path
  rescue GuestBookings::ReserveSlot::Unavailable,
         GuestBookings::CompleteEmergencyUnpaidBooking::Unavailable,
         Billing::ConsultationPrice::Unavailable
    redirect_to guest_booking_review_path, alert: "Emergency booking is unavailable. Please review your reservation or contact the practice."
  end

  def emergency_confirmation
    @appointment = Appointment.joins(:patient).find_by!(
      id: session[:guest_emergency_appointment_id],
      patients: { id: GuestBooking.where(id: session[:guest_booking_id], status: "completed").select(:patient_id) }
    )
    @charge = @appointment.appointment_charges.active.first!
  end

  def payment_status
    guest = GuestBooking.find_by!(id: session[:guest_booking_id])
    @payment = Payment.find_by!(guest_booking: guest, id: params[:id])
    begin
      Payments::ReconcileStripeStatus.new(payment: @payment).call
    rescue Stripe::StripeError => error
      Rails.logger.warn("Guest payment reconciliation unavailable: #{error.class}")
    end
    @payment.reload
  end

  def index
    @practices = Practice.where(
      id: AvailabilityBlock.active.where(bookable_online: true).select(:practice_id)
    ).order(:name)

    @practice = @practices.find_by(id: params[:practice_id]) if params[:practice_id].present?
    @clinicians = []
    @slots = []

    return unless @practice

    @clinicians = @practice.staff_members
      .where(staff_type: %w[ doctor nurse ], active: true)
      .where(id: @practice.availability_blocks.active.where(bookable_online: true).select(:clinician_id))
      .order(:last_name, :first_name).to_a

    @clinician = @clinicians.find { |candidate| candidate.id.to_s == params[:clinician_id].to_s }
    return unless @clinician

    @slots = Appointments::AvailableSlots.new(
      practice: @practice,
      clinician: @clinician,
      date: params[:date],
      online_only: true
    ).call.to_a

    @consultation_fee = @practice.consultation_fees.find_by(clinician_type: @clinician.staff_type)
  end
  private

  def session_guest_booking
    GuestBooking.where(id: session[:guest_booking_id])
      .where(status: %w[draft payment_pending])
      .first!
  end

  def guest_booking_params
    params.require(:guest_booking).permit(
      :first_name, :last_name, :date_of_birth, :email, :phone, :consultation_reason,
      :appointment_slot_id
    )
  end

  def public_slot_scope
    AppointmentSlot.joins(:availability_block, :clinician)
      .merge(AvailabilityBlock.active)
      .where(availability_blocks: { bookable_online: true })
      .where(staff_members: { active: true, staff_type: %w[ doctor nurse ] })
      .where("appointment_slots.starts_at > ?", Time.current)
      .where.not(id: Appointment.where.not(status: "cancelled").select(:appointment_slot_id))
      .where.not(id: AppointmentHold.active.select(:appointment_slot_id))
  end
end
