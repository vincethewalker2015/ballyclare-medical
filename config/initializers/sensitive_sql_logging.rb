# SQL bind values can contain patient contact details and clinical information.
# Rails parameter filtering does not redact Active Record SQL logs.
# Disable Active Record query logging across application environments, while
# keeping controller, job, warning and error logging enabled.
Rails.application.config.after_initialize do
  ActiveRecord::Base.logger = nil
end
