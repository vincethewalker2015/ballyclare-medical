module Staff
  class DocumentationController < BaseController
    def user_manual
      markdown = Rails.root.join("docs/user_manual.md").read
      markdown = markdown.gsub(%r{\]\(images/user_manual/([a-z0-9-]+\.(?:png|svg))\)}) do
        "](/docs/images/user_manual/#{Regexp.last_match(1)})"
      end

      renderer = Redcarpet::Render::HTML.new(
        filter_html: true,
        safe_links_only: true,
        with_toc_data: true
      )

      @manual_html = Redcarpet::Markdown.new(
        renderer,
        autolink: true,
        fenced_code_blocks: true,
        tables: true
      ).render(markdown)
    end

    def image
      image_path = case params[:image]
      when "patient-portal-overview-illustration.svg"
        Rails.root.join("docs/images/user_manual/patient-portal-overview-illustration.svg")
      when "clinician-availability-illustration.svg"
        Rails.root.join("docs/images/user_manual/clinician-availability-illustration.svg")
      when "appointment-booking-illustration.svg"
        Rails.root.join("docs/images/user_manual/appointment-booking-illustration.svg")
      when "practice-switching-illustration.svg"
        Rails.root.join("docs/images/user_manual/practice-switching-illustration.svg")
      when "appointment-diary-illustration.svg"
        Rails.root.join("docs/images/user_manual/appointment-diary-illustration.svg")
      when "patients-list-illustration.png"
        Rails.root.join("docs/images/user_manual/patients-list-illustration.png")
      when "new-patient-illustration.png"
        Rails.root.join("docs/images/user_manual/new-patient-illustration.png")
      when "staff-directory-illustration.png"
        Rails.root.join("docs/images/user_manual/staff-directory-illustration.png")
      when "new-staff-member-illustration.png"
        Rails.root.join("docs/images/user_manual/new-staff-member-illustration.png")
      when "staff-invitation-flow-illustration.png"
        Rails.root.join("docs/images/user_manual/staff-invitation-flow-illustration.png")
      end

      return head :not_found unless image_path&.file?

      send_file image_path, type: (image_path.extname == ".svg" ? "image/svg+xml" : "image/png"), disposition: "inline"
    end
  end
end
