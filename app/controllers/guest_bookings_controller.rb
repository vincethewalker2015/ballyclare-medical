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
    @guest_booking = GuestBooking.new(guest_booking_params.merge(
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
  end

  def checkout
    guest = session_guest_booking
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

  def payment_status
    guest = GuestBooking.find_by!(id: session[:guest_booking_id])
    @payment = Payment.find_by!(guest_booking: guest, id: params[:id])
    begin
      Payments::ReconcileStripeStatus.new(payment: @payment).call
    rescue Stripe::StripeError => error
      Rails.logger.warn("Guest payment reconciliation unavailable: #{error.class}")
    end
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
      :first_name, :last_name, :date_of_birth, :email, :phone, :consultation_reason
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
