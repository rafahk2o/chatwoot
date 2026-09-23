# Melck fork: point the logo configs at versioned URLs so browsers that cached
# the stock Chatwoot logos (public/ is served with a 1-year max-age) refetch them.
class CacheBustMelckLogos < ActiveRecord::Migration[7.1]
  VERSION_SUFFIX = '?v=melck1'.freeze
  LOGOS = {
    'LOGO' => '/brand-assets/logo.svg',
    'LOGO_DARK' => '/brand-assets/logo_dark.svg',
    'LOGO_THUMBNAIL' => '/brand-assets/logo_thumbnail.svg'
  }.freeze

  def up
    LOGOS.each do |name, default_path|
      config = InstallationConfig.find_by(name: name)
      next if config.nil? || config.value != default_path

      config.value = default_path + VERSION_SUFFIX
      config.save!
    end

    GlobalConfig.clear_cache
  end

  def down; end
end
