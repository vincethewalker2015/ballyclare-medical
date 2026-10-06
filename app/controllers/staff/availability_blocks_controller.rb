module Staff
  class AvailabilityBlocksController < BaseController
    def index
      @availability_blocks = current_practice
        .availability_blocks
        .includes(:clinician, :appointment_slots)
        .where(ends_at: Time.current..)
        .order(:starts_at)
    end

    def new
      @availability_block = current_practice.availability_blocks.new(
        slot_duration_minutes: 30,
        bookable_online: true
      )

      load_clinicians
    end

    def create
      clinician = current_practice
        .staff_members
        .where(staff_type: %w[doctor nurse])
        .find(availability_block_params[:clinician_id])

      starts_at = local_time(
        availability_block_params[:date],
        availability_block_params[:starts_at]
      )

      ends_at = local_time(
        availability_block_params[:date],
        availability_block_params[:ends_at]
      )

      @availability_block = current_practice.availability_blocks.new(
        clinician: clinician,
        starts_at: starts_at,
        ends_at: ends_at,
        slot_duration_minutes:
          availability_block_params[:slot_duration_minutes],
        bookable_online:
          availability_block_params[:bookable_online]
      )

      if @availability_block.valid?
        AvailabilityBlock.transaction do
          @availability_block.save!

          Availability::GenerateSlots.new(
            @availability_block
          ).call
        end

        redirect_to practice_availability_blocks_path,
                    notice: "Availability added."
      else
        load_clinicians

        render :new,
               status: :unprocessable_entity
      end
    rescue ArgumentError
      @availability_block ||= current_practice.availability_blocks.new
      @availability_block.errors.add(
        :base,
        "Enter a valid date and time."
      )

      load_clinicians

      render :new,
             status: :unprocessable_entity
    end

    private

    def load_clinicians
      @clinicians = current_practice
        .staff_members
        .where(staff_type: %w[doctor nurse])
        .order(:last_name, :first_name)
    end

    def availability_block_params
      params.require(:availability_block).permit(
        :clinician_id,
        :date,
        :starts_at,
        :ends_at,
        :slot_duration_minutes,
        :bookable_online
      )
    end

    def local_time(date, time)
      raise ArgumentError if date.blank? || time.blank?

      Time.use_zone(current_practice.timezone) do
        Time.zone.parse("#{date} #{time}") ||
          raise(ArgumentError)
      end
    end
  end
end
