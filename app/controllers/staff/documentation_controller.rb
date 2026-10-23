module Staff
  class DocumentationController < BaseController
    def user_manual
      markdown = Rails.root.join("docs/user_manual.md").read
      markdown = markdown.gsub(%r{\]\(images/user_manual/([a-z0-9-]+\.png)\)}) do
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

      send_file image_path, type: "image/png", disposition: "inline"
    end
  end
end
