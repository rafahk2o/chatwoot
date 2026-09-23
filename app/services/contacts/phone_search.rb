# Melck fork: lets agents find contacts by phone typed in any format.
#
# Numbers are stored in E.164, and a third of them in the old WhatsApp form
# without the mobile 9 (+55 DDD 8 digits). A search for "(12) 99627-3723"
# therefore missed "+551296273723". For phone-looking queries this matches on
# digits only, ignoring the +55 prefix and trying the number with and without
# the 9.
class Contacts::PhoneSearch
  PHONE_LIKE = /\A[\d\s()+\-.]+\z/
  MIN_DIGITS = 8

  def initialize(query)
    @query = query.to_s.strip
  end

  def phone_like?
    @query.match?(PHONE_LIKE) && digits.length >= MIN_DIGITS
  end

  # Digit sequences to look for inside the stored number.
  def patterns
    return [] unless phone_like?

    national = digits.start_with?('55') && digits.length >= 12 ? digits[2..] : digits
    variants = [national]
    case national.length
    when 11 then variants << (national[0, 2] + national[3..]) if national[2] == '9' # DDD 9XXXX-XXXX -> DDD XXXX-XXXX
    when 10 then variants << "#{national[0, 2]}9#{national[2..]}" # DDD XXXX-XXXX -> DDD 9XXXX-XXXX
    when 9 then variants << national[1..] if national.start_with?('9')
    when 8 then variants << "9#{national}"
    end
    variants.uniq
  end

  # " OR (<column> LIKE '%...%' OR ...)" to append to an existing search clause, or "".
  def or_sql(column)
    return '' if patterns.empty?

    clauses = patterns.map { |pattern| ActiveRecord::Base.sanitize_sql_array(["#{column} LIKE ?", "%#{pattern}%"]) }
    " OR (#{clauses.join(' OR ')})"
  end

  private

  def digits
    @digits ||= @query.gsub(/\D/, '')
  end
end
