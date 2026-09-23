require 'rails_helper'

describe Messages::VcardContentService do
  let(:account) { create(:account) }
  let(:header) { described_class::HEADER }
  let(:iphone_vcard) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:;;;;\r\nFN:Rodrigues Cargas\r\n" \
      "item1.TEL;waid=554891913279:+55 48 9191-3279\r\nitem1.X-ABLabel:Celular\r\n" \
      "PHOTO;BASE64:/9j/4AAQSkZJRgABAQAAAQABAAD\r\n 4gHYSUNDX1BST0ZJTEUAAQEAAAHI\r\nEND:VCARD\r\n"
  end
  let(:android_vcard) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Coelho;Aurélio;;;\r\n" \
      "TEL;type=CELL;type=VOICE;waid=5512982245609:+55 12 98224-5609\r\nEND:VCARD\r\n"
  end

  def message_with_vcards(content:, vcards:, message_type: 'incoming')
    message = build(:message, account: account, content: content, message_type: message_type)
    vcards.each_with_index do |vcard, index|
      attachment = message.attachments.new(account_id: account.id, file_type: :file)
      attachment.file.attach(io: StringIO.new(vcard), filename: "vcard-#{index + 1}.vcf", content_type: 'text/vcard')
    end
    message.save!
    message
  end

  it 'fills in names and phones when the bridge sent only the header' do
    message = message_with_vcards(content: "#{header}\n\n", vcards: [iphone_vcard, android_vcard])

    expect(described_class.new(message: message).perform).to be(true)

    expect(message.reload.content).to eq(
      "#{header}\n\n🪪 Nome: **Rodrigues Cargas**\n- 📞 Telefone: **+55 48 9191-3279**\n\n" \
      "🪪 Nome: **Aurélio Coelho**\n- 📞 Telefone: **+55 12 98224-5609**"
    )
  end

  it 'keeps other text and appends the contacts' do
    message = message_with_vcards(content: 'segue a referência', vcards: [android_vcard])

    described_class.new(message: message).perform

    expect(message.reload.content).to start_with("segue a referência\n\n🪪 Nome: **Aurélio Coelho**")
  end

  it 'leaves messages that already show the contacts untouched' do
    content = "#{header}\n\n🪪 Nome: **Aurélio Coelho**\n- 📞 Telefone: **+55 12 98224-5609**"
    message = message_with_vcards(content: content, vcards: [android_vcard])

    expect(described_class.new(message: message).perform).to be(false)
    expect(message.reload.content).to eq(content)
  end

  it 'ignores outgoing messages' do
    message = message_with_vcards(content: header, vcards: [android_vcard], message_type: 'outgoing')

    expect(described_class.new(message: message).perform).to be(false)
  end

  it 'broadcasts to the dashboard without firing message_updated webhooks' do
    message = message_with_vcards(content: header, vcards: [android_vcard])
    allow(ActionCableListener.instance).to receive(:message_updated)
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    described_class.new(message: message).perform

    expect(ActionCableListener.instance).to have_received(:message_updated)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
  end
end
