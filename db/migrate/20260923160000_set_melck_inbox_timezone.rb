# Melck fork: inboxes were left on the stock UTC / America/Los_Angeles
# timezones, so transcripts showed message times in the wrong zone. Only
# inboxes without business hours are touched, so no schedule shifts.
class SetMelckInboxTimezone < ActiveRecord::Migration[7.1]
  def up
    Inbox.where(working_hours_enabled: false, timezone: [nil, '', 'UTC', 'America/Los_Angeles'])
         .update_all(timezone: 'America/Sao_Paulo')
  end

  def down; end
end
