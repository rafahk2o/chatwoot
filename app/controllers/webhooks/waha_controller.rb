class Webhooks::WahaController < ActionController::API
  before_action :verify_secret!

  def process_payload
    Webhooks::WahaForwardedMessageJob.set(wait: 15.seconds).perform_later(chat_ids) if forwarded_direct_message?
    head :ok
  end

  private

  def verify_secret!
    return if ActiveSupport::SecurityUtils.secure_compare(request.headers['X-Webhook-Secret'].to_s, ENV.fetch('WAHA_WEBHOOK_SECRET'))

    head :unauthorized
  end

  def message_data
    @message_data ||= params.to_unsafe_h.dig(:payload, :_data) || {}
  end

  def forwarded_direct_message?
    return false unless params[:event] == 'message' && !message_data.dig(:Info, :IsGroup)

    (message_data[:Message] || {}).values.any? do |content|
      context = content[:contextInfo] if content.is_a?(Hash)
      context.present? && (context[:isForwarded] || context[:forwardingScore].to_i.positive?)
    end
  end

  def chat_ids
    [params.dig(:payload, :from), message_data.dig(:Info, :SenderAlt)].compact
  end
end
