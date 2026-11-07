module ClinicalDocuments
  class RenderPdf
    def initialize(release:)
      @release = release
    end

    def call
      Prawn::Document.new(page_size: "A4", margin: 54) do |pdf|
        pdf.font "Helvetica"
        pdf.text @release.practice.name, size: 17, style: :bold
        pdf.move_down 22
        pdf.text @release.title, size: 15, style: :bold
        pdf.move_down 15
        pdf.text "Patient: #{@release.patient.first_name} #{@release.patient.last_name}"
        pdf.text "Patient number: #{@release.patient.patient_number}"
        pdf.text "Issued: #{@release.released_at.in_time_zone(@release.practice.timezone).strftime('%d %B %Y')}"
        pdf.text "Clinician: #{@release.released_by.full_name}"
        pdf.move_down 22
        pdf.text @release.body, size: 11, leading: 5
      end.render
    end
  end
end