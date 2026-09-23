namespace :melck do
  desc 'Fill in past shared-contact messages whose text came in blank (see Messages::VcardContentService)'
  task backfill_vcard_contents: :environment do
    scope = Message.incoming.where('content ILIKE ?', '%Contato(s) compartilhado%').where.not('content ILIKE ?', '%Telefone%')
    total = scope.count
    fixed = 0
    scope.includes(attachments: { file_attachment: :blob }).find_each do |message|
      fixed += 1 if Messages::VcardContentService.new(message: message, broadcast: false).perform
    rescue StandardError => e
      Rails.logger.warn("vcard backfill skipped message #{message.id}: #{e.class}: #{e.message}")
    end
    puts "Filled in #{fixed} of #{total} messages"
  end
end
