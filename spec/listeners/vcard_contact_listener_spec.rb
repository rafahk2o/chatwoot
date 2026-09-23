require 'rails_helper'

describe VcardContactListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }

  def event_for(message)
    Events::Base.new(Events::Types::MESSAGE_CREATED, Time.zone.now, message: message)
  end

  it 'enqueues the vCard job for incoming messages with attachments' do
    message = create(:message, :with_attachment, account: account, message_type: 'incoming')

    expect { listener.message_created(event_for(message)) }
      .to have_enqueued_job(Messages::VcardContentJob).with(message)
  end

  it 'skips messages without attachments' do
    message = create(:message, account: account, message_type: 'incoming')

    expect { listener.message_created(event_for(message)) }.not_to have_enqueued_job(Messages::VcardContentJob)
  end
end
