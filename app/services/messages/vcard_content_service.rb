# Melck fork: fills in the text of incoming messages that carry shared contacts
# (.vcf attachments) when the WhatsApp bridge could not read them.
#
# The bridge (WAHA) posts a "Contato(s) compartilhado(s)" header plus the
# vCards, but for vCards in the iPhone/Google format (grouped `item1.TEL`,
# embedded PHOTO) the names and numbers come out empty, so agents saw a blank
# message. This rebuilds the text from the attached vCards.
#
# The content is written with update_columns and only broadcast to the agents'
# dashboard: a regular update would fire `message_updated` webhooks back to the
# bridge and to account integrations.
class Messages::VcardContentService
  HEADER = '👤 **Contato(s) compartilhado(s)**'.freeze

  def initialize(message:, broadcast: true)
    @message = message
    @broadcast = broadcast
  end

  def perform
    return false unless @message.incoming?

    contacts = vcard_attachments.map { |attachment| parse(read(attachment)) }.select { |contact| contact[:name] || contact[:phones].any? }
    return false if contacts.empty? || all_phones_present?(contacts)

    update_content(build_content(contacts))
    true
  end

  private

  def vcard_attachments
    @message.attachments.select do |attachment|
      next false unless attachment.file.attached?

      blob = attachment.file.blob
      blob.content_type.to_s.include?('vcard') || blob.filename.to_s.downcase.end_with?('.vcf')
    end
  end

  def read(attachment)
    attachment.file.blob.download.force_encoding(Encoding::UTF_8).scrub('')
  end

  def parse(vcard)
    full_name = nil
    structured_name = nil
    phones = []

    # Unfold continuation lines (RFC 6350 3.2), e.g. base64 PHOTO data.
    vcard.gsub(/\r?\n[ \t]/, '').each_line do |line|
      key, value = line.chomp.split(':', 2)
      next if value.blank?

      # `item1.TEL;waid=...` -> TEL
      case key.split(';').first.to_s.split('.').last.to_s.upcase
      when 'FN' then full_name = value.strip
      when 'N' then structured_name = value.split(';').values_at(1, 2, 0).compact_blank.join(' ').strip
      when 'TEL' then phones << value.strip
      end
    end

    { name: full_name.presence || structured_name.presence, phones: phones.compact_blank.uniq }
  end

  def all_phones_present?(contacts)
    digits = @message.content.to_s.gsub(/\D/, '')
    contacts.flat_map { |contact| contact[:phones] }.all? { |phone| digits.include?(phone.gsub(/\D/, '')) } &&
      contacts.all? { |contact| contact[:name].blank? || @message.content.to_s.include?(contact[:name]) }
  end

  def build_content(contacts)
    blocks = contacts.map do |contact|
      lines = ["🪪 Nome: **#{contact[:name] || '(sem nome)'}**"]
      lines += contact[:phones].map { |phone| "- 📞 Telefone: **#{phone}**" }
      lines.join("\n")
    end.join("\n\n")

    header_only? ? "#{HEADER}\n\n#{blocks}" : "#{@message.content.to_s.rstrip}\n\n#{blocks}"
  end

  def header_only?
    @message.content.to_s.gsub(/[*\s]|👤/, '').casecmp?('Contato(s)compartilhado(s)') || @message.content.blank?
  end

  def update_content(content)
    previous = @message.content
    @message.update_columns(content: content, processed_message_content: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    return unless @broadcast

    event = Events::Base.new(Events::Types::MESSAGE_UPDATED, Time.zone.now,
                             message: @message, previous_changes: { 'content' => [previous, content] })
    ActionCableListener.instance.message_updated(event)
  end
end
