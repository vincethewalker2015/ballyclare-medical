class GuestBookingsController < ApplicationController
  layout "public"

  def index
    @practices = Practice.where(
      id: AvailabilityBlock.active.where(bookable_online: true).select(:practice_id)
    ).order(:name)
  end
end
