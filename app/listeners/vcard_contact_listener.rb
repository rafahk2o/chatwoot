# Melck fork: fills in shared-contact messages whose text came in blank.
class VcardContactListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    return unless message.incoming? && message.attachments.any?

    Messages::VcardContentJob.perform_later(message)
  end
end
