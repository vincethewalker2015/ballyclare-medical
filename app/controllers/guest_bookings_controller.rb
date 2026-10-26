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
    head :not_implemented
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
