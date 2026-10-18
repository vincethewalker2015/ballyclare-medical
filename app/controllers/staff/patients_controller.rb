module Staff
  class PatientsController < BaseController
    def index
      @patients = current_practice.patients.order(:last_name, :first_name)
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
        :patient_number, :first_name, :last_name, :date_of_birth
      )
    end
  end
end
