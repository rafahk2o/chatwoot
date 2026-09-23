require 'rails_helper'

describe Contacts::PhoneSearch do
  def patterns(query)
    described_class.new(query).patterns
  end

  it 'matches on digits only, with and without the mobile 9' do
    expect(patterns('(12) 99627-3723')).to contain_exactly('12996273723', '1296273723')
  end

  it 'drops the +55 country code' do
    expect(patterns('+55 12 99627-3723')).to contain_exactly('12996273723', '1296273723')
  end

  it 'adds the 9 to old-format numbers' do
    expect(patterns('12 9627-3723')).to contain_exactly('1296273723', '12996273723')
  end

  it 'handles numbers typed without the area code' do
    expect(patterns('99627-3723')).to contain_exactly('996273723', '96273723')
    expect(patterns('9627-3723')).to contain_exactly('96273723', '996273723')
  end

  it 'ignores queries that do not look like a phone' do
    expect(patterns('Motorista 12 99627')).to be_empty
    expect(patterns('1234')).to be_empty
    expect(described_class.new('joao').or_sql('phone_number')).to eq('')
  end

  describe 'with stored contacts' do
    let(:account) { create(:account) }
    let!(:old_format) { create(:contact, account: account, phone_number: '+551296273723') }
    let!(:new_format) { create(:contact, account: account, phone_number: '+5541997166249') }

    def search(query)
      account.contacts.where("name ILIKE 'x'#{described_class.new(query).or_sql('phone_number')}")
    end

    it 'finds a number stored without the 9 when typed with it' do
      expect(search('(12) 99627-3723')).to contain_exactly(old_format)
    end

    it 'finds a number stored with the 9 when typed without it' do
      expect(search('41 9716-6249')).to contain_exactly(new_format)
    end
  end
end
