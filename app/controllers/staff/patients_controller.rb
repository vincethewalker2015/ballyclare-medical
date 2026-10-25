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
    end

    def create
      @patient = current_practice.patients.new(patient_params)

      if @patient.save
        redirect_to practice_patients_path, notice: "Patient created successfully."
      else
        render :new, status: :unprocessable_content
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
