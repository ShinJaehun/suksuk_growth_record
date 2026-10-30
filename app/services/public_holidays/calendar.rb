module PublicHolidays
  # Reuse the praise calendar's KASI client without its database sync lifecycle.
  class Calendar
    def self.for_year(year, client: KasiClient.new, cache: Rails.cache)
      cache.fetch("public_holidays/kasi/#{year}", expires_in: 12.hours) do
        holidays = client.fetch_year(year)
        raise KasiClient::ResponseError, "KASI holiday API returned no holidays" if holidays.empty?

        holidays
      end
    rescue KasiClient::Error
      nil
    end
  end
end
