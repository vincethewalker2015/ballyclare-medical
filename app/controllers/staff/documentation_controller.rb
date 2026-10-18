module Staff
  class DocumentationController < BaseController
    def user_manual
      markdown = Rails.root.join("docs/user_manual.md").read
      markdown = markdown.gsub(%r{\]\(images/user_manual/([a-z0-9-]+\.png)\)}) do
        "](/docs/images/user_manual/#{Regexp.last_match(1)})"
      end

      renderer = Redcarpet::Render::HTML.new(
        filter_html: true,
        safe_links_only: true
      )

      @manual_html = Redcarpet::Markdown.new(
        renderer,
        autolink: true,
        fenced_code_blocks: true,
        tables: true
      ).render(markdown)
    end

    def image
      filename = params[:image].to_s
      return head :not_found unless filename.match?(/\A[a-z0-9-]+\.png\z/)

      image_path = Rails.root.join("docs/images/user_manual", filename)
      return head :not_found unless image_path.file?

      send_file image_path, type: "image/png", disposition: "inline"
    end
  end
end
