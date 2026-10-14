module Staff
  class DocumentationController < BaseController
    def user_manual
      markdown = Rails.root.join("docs/user_manual.md").read

      renderer = Redcarpet::Render::HTML.new(
        filter_html: true,
        no_images: true,
        safe_links_only: true
      )

      @manual_html = Redcarpet::Markdown.new(
        renderer,
        autolink: true,
        fenced_code_blocks: true,
        tables: true
      ).render(markdown)
    end
  end
end
