class GuestBookingsController < ApplicationController
  layout "public"

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
end
