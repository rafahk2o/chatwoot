# Melck fork: accounts still carry the stock "Chatwoot <accounts@chatwoot.com>"
# support email, which conversation emails (e.g. transcripts) use as sender.
# Gmail SMTP will not send as chatwoot.com, so use the configured sender instead.
class SetMelckAccountSupportEmail < ActiveRecord::Migration[7.1]
  def up
    sender = Mail::Address.new(ENV.fetch('MAILER_SENDER_EMAIL', '')).address
    return if sender.blank? || sender.end_with?('@chatwoot.com')

    Account.where(support_email: [nil, ''])
           .or(Account.where('support_email ILIKE ?', '%@chatwoot.com%'))
           .update_all(support_email: "Melck <#{sender}>") # rubocop:disable Rails/SkipsModelValidations -- avoid account_updated webhooks
  rescue Mail::Field::ParseError
    nil
  end

  def down; end
end
