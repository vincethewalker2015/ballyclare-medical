module Staff
  class ConsultationFeesController < BaseController
    before_action :require_fee_administrator

    def edit
      load_fees
    end

    def update
      amounts = params.require(:consultation_fees).permit(:doctor, :nurse)
      parsed = ConsultationFee::CLINICIAN_TYPES.index_with do |type|
        parse_amount(amounts[type])
      end

      if parsed.values.any?(&:nil?)
        load_fees
        flash.now[:alert] = "Enter a positive amount with no more than two decimal places for both consultations."
        return render :edit, status: :unprocessable_content
      end

      ConsultationFee.transaction do
        current_practice.lock!
        parsed.each do |type, cents|
          fee = current_practice.consultation_fees.find_or_initialize_by(clinician_type: type)
          previous = fee.amount_cents if fee.persisted?
          fee.update!(amount_cents: cents, currency: current_practice.currency)
          next if previous == cents

          AuditEvent.create!(
            practice: current_practice,
            user: current_user,
            auditable: fee,
            action: "consultation_fee.updated",
            metadata: { clinician_type: type, old_amount_cents: previous,
                        new_amount_cents: cents, currency: fee.currency }
          )
        end
      end

      redirect_to edit_practice_consultation_fees_path, notice: "Consultation fees updated."
    end

    private

    def require_fee_administrator
      head :forbidden unless current_staff_member.staff_administration_access?
    end

    def load_fees
      @fees = current_practice.consultation_fees.index_by(&:clinician_type)
    end

    def parse_amount(value)
      value = value.to_s.strip
      return nil unless value.match?(/\A\d+(?:\.\d{1,2})?\z/)

      cents = (BigDecimal(value) * 100).to_i
      cents if cents.positive? && cents <= 100_000_000
    end
  end
end
