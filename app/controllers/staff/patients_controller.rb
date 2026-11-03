module Staff
  class PatientsController < BaseController
    before_action :require_operational_access
    def index
      @patient_search = params[:patient_search].to_s.strip.first(100)
      @patients = current_practice.patients

      if @patient_search.present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(@patient_search)}%"
        @patients = @patients.where(
          "first_name ILIKE :term OR last_name ILIKE :term OR " \
          "patient_number ILIKE :term OR " \
          "CONCAT_WS(' ', first_name, last_name) ILIKE :term",
          term: term
        )
      end

      @patients = @patients.order(:last_name, :first_name).limit(100)
    end

    def new
      @patient = current_practice.patients.new
      @invite_to_portal = false
    end

    def create
      @patient = current_practice.patients.new(patient_params)
      @invite_to_portal = params.dig(:patient, :invite_to_portal) == "1"
      email = params.dig(:patient, :email).to_s.strip
      account = nil

      if @invite_to_portal && !current_staff_member.staff_administration_access?
        return head :forbidden
      end

      begin
        Patient.transaction do
          @patient.save!
          if @invite_to_portal
            account = PatientAccounts::CreateInvitation.call!(
              patient: @patient, email: email, staff_member: current_staff_member
            )
          end
        end
      rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
        @patient.errors.add(:base, error.message) if error.is_a?(ArgumentError)
        @patient.errors.add(:base, "Could not create the patient and invitation.") if @patient.errors.empty?
        return render :new, status: :unprocessable_content
      end

      PatientPortalActivationJob.perform_later(account.id) if account
      if account
        redirect_to practice_patient_path(@patient),
          notice: "Patient created and portal invitation queued. Identity verification and senior approval are still required."
      else
        redirect_to practice_patients_path, notice: "Patient created successfully."
      end
    end

    def show
      @patient = current_practice.patients.find(params[:id])
    end

    def edit
      @patient = current_practice.patients.find(params[:id])
    end

    def update
      @patient = current_practice.patients.find(params[:id])

      if @patient.update(patient_params)
        redirect_to practice_patient_path(@patient), notice: "Patient updated successfully."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def patient_params
      params.require(:patient).permit(
        :first_name, :last_name, :date_of_birth
      )
    end
  end
end
