class Webhooks::WahaMessageAlertJob < ApplicationJob
  queue_as :default

  WAHA_CHAT_ID_ATTRIBUTES = %w[waha_whatsapp_chat_id waha_whatsapp_lid waha_whatsapp_jid].freeze

  # WAHA's Chatwoot app creates the contact and conversation from its own copy of the event,
  # so they may not exist yet when this job first runs.
  retry_on ActiveRecord::RecordNotFound, wait: 15.seconds, attempts: 4 do |job, error|
    Rails.logger.warn "WAHA message alert skipped for #{job.arguments.first}: #{error.message}"
  end

  def perform(chat_ids, reason)
    conversation = find_contact(chat_ids).conversations.joins(:inbox)
                                         .where(inboxes: { channel_type: 'Channel::Api' })
                                         .order(last_activity_at: :desc).first!

    Messages::MessageBuilder.new(nil, conversation, { content: I18n.t("conversations.messages.waha.#{reason}"), private: true }).perform
  end

  private

  def find_contact(chat_ids)
    phone_numbers = chat_ids.grep(/@(s\.whatsapp\.net|c\.us)\z/).map { |chat_id| "+#{chat_id.split('@').first}" }

    WAHA_CHAT_ID_ATTRIBUTES.map { |attribute| Contact.where('custom_attributes ->> ? IN (?)', attribute, chat_ids) }
                           .reduce(Contact.where(phone_number: phone_numbers), :or).first!
  end
end
