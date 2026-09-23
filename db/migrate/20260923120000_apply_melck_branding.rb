# Melck fork: rename the installation from the stock "Chatwoot" defaults.
# Only touches values still at the default, so edits made in super admin win.
class ApplyMelckBranding < ActiveRecord::Migration[7.1]
  BRAND_NAME = 'Melck'.freeze

  def up
    %w[INSTALLATION_NAME BRAND_NAME].each do |name|
      config = InstallationConfig.find_by(name: name)
      next if config.nil? || config.value != 'Chatwoot'

      config.value = BRAND_NAME
      config.save!
    end

    GlobalConfig.clear_cache
  end

  def down; end
end
