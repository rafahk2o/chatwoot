class Webhooks::WahaController < ActionController::API
  STALE_MEDIA_THRESHOLD = 10.minutes
  MEDIA_FINGERPRINT_TTL = 30.days

  before_action :verify_secret!

  def process_payload
    reason = alert_reason
    Webhooks::WahaMessageAlertJob.set(wait: 15.seconds).perform_later(chat_ids, reason) if reason
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

  def message_contents
    (message_data[:Message] || {}).values.grep(Hash)
  end

  def alert_reason
    return unless params[:event] == 'message' && !message_data.dig(:Info, :IsGroup)
    return 'forwarded_message' if message_contents.any? { |content| forwarded?(content[:contextInfo]) }

    media = message_contents.find { |content| content[:fileSHA256].present? }
    return unless media
    return 'stale_media' if stale_media?(media)

    'duplicate_media' if duplicate_media?(media)
  end

  def forwarded?(context)
    context.present? && (context[:isForwarded] || context[:forwardingScore].to_i.positive?)
  end

  # WhatsApp keeps the original media key timestamp when media is reused instead of uploaded again.
  def stale_media?(media)
    media[:mediaKeyTimestamp].to_i.positive? && params.dig(:payload, :timestamp).to_i - media[:mediaKeyTimestamp].to_i > STALE_MEDIA_THRESHOLD
  end

  # The same file already received from a different contact.
  def duplicate_media?(media)
    key = format(Redis::RedisKeys::WAHA_MEDIA_FINGERPRINT, sha256: media[:fileSHA256])
    sender = params.dig(:payload, :from)
    return false if Redis::Alfred.set(key, sender, nx: true, ex: MEDIA_FINGERPRINT_TTL.to_i)

    Redis::Alfred.get(key) != sender
  end

  def chat_ids
    [params.dig(:payload, :from), message_data.dig(:Info, :SenderAlt)].compact
  end
end
